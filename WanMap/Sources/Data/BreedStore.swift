import Foundation
import Observation

/// 犬種マスタの読み込みと更新（施設と同じ3段構え）
/// 1. サーバー配信JSON（breeds.json、起動時に新しい版があれば差し替え）
/// 2. 前回キャッシュ
/// 3. アプリ同梱JSON（初回・オフライン用）
/// 更新に失敗しても表示・選択が壊れないことを最優先にする。
/// 検索は端末内だけで行い、入力文字列を外へ送らない。
@Observable
final class BreedStore {
    private(set) var breeds: [Breed] = []
    private(set) var version: Int = 0

    /// 配信JSONのURL（施設と同じ公開リポジトリ komoni/wanmap-data）
    var remoteURL: URL? = URL(string: "https://raw.githubusercontent.com/komoni/wanmap-data/main/breeds.json")

    /// 犬種未設定・アイコン未制作のときの代替アイコン（本人の決定：デフォルトはミックス）
    static let fallbackIconAsset = "breed_mixed_brown-white"
    static let genericMixBreedId = "mixed"

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("breeds-cache.json")
    }

    init() {
        loadLocal()
    }

    /// テスト・プレビュー用：マスタを直接渡す
    init(breeds: [Breed], version: Int = 1) {
        self.breeds = breeds
        self.version = version
    }

    private func loadLocal() {
        if let data = try? Data(contentsOf: cacheURL),
           let dataset = try? JSONDecoder().decode(BreedDataset.self, from: data) {
            breeds = dataset.breeds
            version = dataset.version
            return
        }
        if let url = Bundle.main.url(forResource: "breeds", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dataset = try? JSONDecoder().decode(BreedDataset.self, from: data) {
            breeds = dataset.breeds
            version = dataset.version
        }
    }

    /// 起動時に呼ぶ。新しい版があれば差し替える。失敗しても何も壊さない。
    func refreshFromRemote() async {
        guard let remoteURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let dataset = try JSONDecoder().decode(BreedDataset.self, from: data)
            guard dataset.version > version else { return }
            try data.write(to: cacheURL, options: .atomic)
            breeds = dataset.breeds
            version = dataset.version
        } catch {
            // 失敗時は現状維持（キャッシュ or 同梱版のまま）
        }
    }

    // MARK: - 引き当て

    func breed(id: String?) -> Breed? {
        guard let id else { return nil }
        return breeds.first { $0.id == id }
    }

    /// 地図チップに出すアイコンのアセット名。
    /// 犬種未設定・その色のアイコンが未制作なら、汎用ミックスに倒す（本人の決定）。
    func markerIconAsset(breedId: String?, colorId: String?) -> String {
        if let breed = breed(id: breedId),
           let icon = breed.color(id: colorId)?.icon {
            return icon
        }
        return Self.fallbackIconAsset
    }

    /// 設定プレビュー用：選ばれている色のアイコンがあるか（無い色は「準備中」表示にする）
    func hasProducedIcon(breedId: String?, colorId: String?) -> Bool {
        breed(id: breedId)?.color(id: colorId)?.icon != nil
    }

    // MARK: - 並び替え

    func sorted(_ list: [Breed], by sort: BreedSort) -> [Breed] {
        switch sort {
        case .popularity:
            return list.sorted { ($0.popularity, $0.kana, $0.id) < ($1.popularity, $1.kana, $1.id) }
        case .kana:
            return list.sorted { ($0.kana, $0.id) < ($1.kana, $1.id) }
        case .size:
            return list.sorted { ($0.size.sortOrder, $0.kana, $0.id) < ($1.size.sortOrder, $1.kana, $1.id) }
        }
    }

    var allSortedByPopularity: [Breed] { sorted(breeds, by: .popularity) }

    // MARK: - 検索

    /// 検索キー用に正規化する：全角→半角・大文字小文字の統一に加え、
    /// カタカナをひらがなへそろえる（「しば」「シバ」「柴」が同じ候補に届くように）。
    /// 施設検索と違い、長音「ー」は意味のある文字として残す（プードル等の表記を壊さない）。
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "ja_JP")).lowercased()
        var result = ""
        for scalar in folded.unicodeScalars {
            // カタカナ（ァ-ヶ）をひらがなへ
            if (0x30A1...0x30F6).contains(scalar.value),
               let hira = UnicodeScalar(scalar.value - 0x60) {
                result.unicodeScalars.append(hira)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result.filter { !$0.isWhitespace && !"・-‐'’`".contains($0) }
    }

    /// 漢字表記の名前をかな検索に届かせるための補助キー（柴犬→しばいぬ は kana が担う）
    private func searchKeys(for breed: Breed) -> [String] {
        ([breed.name, breed.kana, breed.english] + breed.aliases).map(Self.normalize)
    }

    /// 一致度：0=完全一致、1=前方一致、2=部分一致、nil=不一致
    private func matchLevel(breed: Breed, query: String) -> Int? {
        var best: Int? = nil
        for key in searchKeys(for: breed) {
            if key == query { return 0 }
            if key.hasPrefix(query) { best = min(best ?? 1, 1) }
            else if key.contains(query) { best = min(best ?? 2, 2) }
        }
        return best
    }

    /// 検索：空白で分けた各語が、名前・読み・英名・別名のどれかに一致する犬種を返す（AND）。
    /// 並びは一致度優先、その中では指定の並び替えを適用する。
    func search(_ query: String, sort: BreedSort = .popularity) -> [Breed] {
        let words = query.split(whereSeparator: { $0.isWhitespace })
            .map { Self.normalize(String($0)) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var scored: [(breed: Breed, level: Int)] = []
        for breed in breeds {
            var worst: Int? = nil
            for word in words {
                guard let level = matchLevel(breed: breed, query: word) else { worst = nil; break }
                worst = max(worst ?? 0, level)
            }
            if let worst { scored.append((breed, worst)) }
        }
        let ordered = sorted(scored.map(\.breed), by: sort)
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        return scored
            .sorted { ($0.level, rank[$0.breed.id] ?? 0) < ($1.level, rank[$1.breed.id] ?? 0) }
            .map(\.breed)
    }
}
