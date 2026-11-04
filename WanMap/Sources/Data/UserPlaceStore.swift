import Foundation
import Observation

/// ユーザーが追加した場所の保持と端末内保存
///
/// 仕様（決定済み）：
/// - 公式施設データ（FacilityStore／facilities.json）とは分離し、端末内のJSON
///   （Documents/user_places.json）にだけ保存する。表示・検索の層でのみマージする。
/// - ユーザーが追加・編集した情報は初期施設情報より優先度が高い（候補では先に出す）。
/// - 公開範囲のデフォルトは「招待した人だけ」。共有されるのは場所名のみで、座標は公開しない。
@Observable
final class UserPlaceStore {
    /// 追加済みの場所（追加順）
    private(set) var places: [UserPlace] = []

    private let persists: Bool

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_places.json")
    }

    init() {
        persists = true
        load()
    }

    /// プレビュー専用。端末ファイルには読み書きしない。
    init(samplePlaces: [UserPlace]) {
        persists = false
        places = samplePlaces
    }

    // MARK: - CRUD

    func add(_ place: UserPlace) {
        places.append(place)
        save()
    }

    func update(_ place: UserPlace) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index] = place
        save()
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
        save()
    }

    func remove(_ place: UserPlace) {
        remove(id: place.id)
    }

    /// 設定画面の「データをリセット」用
    func resetAll() {
        places = []
        save()
    }

    // MARK: - 検索

    /// 場所名検索：施設検索と正規化ルールを共有し、表記ゆれを吸収する
    func search(_ query: String) -> [UserPlace] {
        let q = FacilityStore.normalize(query)
        guard !q.isEmpty else { return [] }
        return places.filter { FacilityStore.normalize($0.name).contains(q) }
    }

    // MARK: - 内部処理

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.makeDecoder().decode([UserPlace].self, from: data)
        else { return }
        places = decoded
    }

    private func save() {
        guard persists else { return }
        guard let data = try? Self.makeEncoder().encode(places) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
