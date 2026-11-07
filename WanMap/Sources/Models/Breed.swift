import Foundation

/// 犬種マスタ（breeds.json の1犬種分）
/// - IDは不変。名前・人気順が変わっても変えない（犬の設定はIDで持つ）。
/// - 画像の制作状況と犬種の分類は別情報：アイコン未制作でも色は選べる
///   （icon が nil の色は「準備中」表示になり、地図では汎用ミックスで代替する）。
struct Breed: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var kana: String            // 読み（ひらがな）。検索・50音順のキー
    var english: String
    var size: BreedSize
    var kind: BreedKind
    var popularity: Int         // 並び替え「人気順」の順位（小さいほど上位）
    var aliases: [String]       // 別名・略称（トイプー、シェルティ等）
    var colors: [BreedColor]

    func color(id: String?) -> BreedColor? {
        guard let id else { return nil }
        return colors.first { $0.id == id }
    }
}

struct BreedColor: Codable, Identifiable, Equatable {
    let id: String              // 犬種内で不変（毛色だけのID。全体では breedId と組で一意）
    var name: String
    /// 同梱済みアイコンのアセット名。未制作は nil
    var icon: String?
}

enum BreedSize: String, Codable, CaseIterable {
    case small, medium, large, varies

    var displayName: String {
        switch self {
        case .small: return "小型"
        case .medium: return "中型"
        case .large: return "大型"
        case .varies: return "さまざま"
        }
    }

    /// サイズ順の並び（小型→中型→大型→さまざま）
    var sortOrder: Int {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        case .varies: return 3
        }
    }
}

enum BreedKind: String, Codable {
    case purebred, namedMix, genericMix, other
}

struct BreedDataset: Codable {
    var version: Int
    var breeds: [Breed]
}

/// 犬種の並び替え（犬種選択画面）
enum BreedSort: String, CaseIterable {
    case popularity, kana, size

    var displayName: String {
        switch self {
        case .popularity: return "人気順"
        case .kana: return "50音順"
        case .size: return "サイズ順"
        }
    }
}

/// 地図チップの種類（設定で選ぶ。既定は頭文字＝現状の表示）
enum MarkerChipStyle: String, CaseIterable {
    case initial, breedIcon

    var displayName: String {
        switch self {
        case .initial: return "頭文字"
        case .breedIcon: return "犬種アイコン"
        }
    }
}
