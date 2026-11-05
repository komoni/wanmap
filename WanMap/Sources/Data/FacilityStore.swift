import Foundation
import Observation

/// 施設データの読み込みと更新
///
/// 3段構え（DATA_UPDATE_DESIGN.md）：
/// 1. サーバー配信JSON（起動時にバージョンチェックして差し替え）
/// 2. 前回キャッシュ
/// 3. アプリ同梱JSON（初回・オフライン用）
/// 更新に失敗しても表示が壊れないことを最優先にする。
@Observable
final class FacilityStore {
    private(set) var facilities: [Facility] = []
    private(set) var version: Int = 0

    /// 配信JSONのURL（公開リポジトリ komoni/wanmap-data、2026-11-05に本人の決定で配信開始）
    var remoteURL: URL? = URL(string: "https://raw.githubusercontent.com/komoni/wanmap-data/main/facilities.json")

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("facilities-cache.json")
    }

    init() {
        loadLocal()
    }

    private func loadLocal() {
        if let data = try? Data(contentsOf: cacheURL),
           let dataset = try? JSONDecoder().decode(FacilityDataset.self, from: data) {
            facilities = dataset.facilities
            version = dataset.version
            return
        }
        if let url = Bundle.main.url(forResource: "facilities", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dataset = try? JSONDecoder().decode(FacilityDataset.self, from: data) {
            facilities = dataset.facilities
            version = dataset.version
        }
    }

    /// 起動時に呼ぶ。新しい版があれば差し替える。失敗しても何も壊さない。
    func refreshFromRemote() async {
        guard let remoteURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let dataset = try JSONDecoder().decode(FacilityDataset.self, from: data)
            guard dataset.version > version else { return }
            try data.write(to: cacheURL, options: .atomic)
            facilities = dataset.facilities
            version = dataset.version
        } catch {
            // 失敗時は現状維持（キャッシュ or 同梱版のまま）
        }
    }

    /// 施設名検索：大文字小文字・全角半角・記号の違いを吸収する（プロトタイプのバグ修正を踏襲）
    func search(_ query: String) -> [Facility] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        return facilities.filter {
            Self.normalize($0.name).contains(q) || Self.normalize($0.displayName).contains(q)
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .lowercased()
            .filter { !$0.isWhitespace && !"'\u{2019}`・-ー".contains($0) }
    }
}
