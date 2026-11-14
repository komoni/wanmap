import Foundation
import Observation

/// 地図チップの種類の設定（設定タブ「地図の表示」）
/// 既定は犬種アイコン（2026-11-14、本人の指示で頭文字から変更）。
/// 頭文字は設定で選んだ時だけ使う。
/// FeedbackSettings と同じく、変更したら即 UserDefaults に保存する。
@Observable
final class MarkerSettings {
    private static let chipStyleKey = "wanmap.marker.chipStyle"
    /// 犬種選択画面の並び替えの記憶（本人が変えた並びは次回もその並びで開く）
    private static let breedSortKey = "wanmap.breed.sort"
    /// 並びの向き（true=上から＝昇順、false=下から＝降順）の記憶
    private static let breedSortAscendingKey = "wanmap.breed.sortAscending"

    private let defaults: UserDefaults

    var chipStyle: MarkerChipStyle {
        didSet { defaults.set(chipStyle.rawValue, forKey: Self.chipStyleKey) }
    }

    var breedSort: BreedSort {
        didSet { defaults.set(breedSort.rawValue, forKey: Self.breedSortKey) }
    }

    var breedSortAscending: Bool {
        didSet { defaults.set(breedSortAscending, forKey: Self.breedSortAscendingKey) }
    }

    init(defaults: UserDefaults = .standard, launchArguments: [String] = []) {
        self.defaults = defaults
        var style = defaults.string(forKey: Self.chipStyleKey)
            .flatMap(MarkerChipStyle.init(rawValue:)) ?? .breedIcon
        // 画面撮影用（DEBUGの起動引数 -wmChipStyle breedIcon / initial）。
        // AppearanceStore と同じ流儀で、引数があれば保存値より優先する。
        // init 内の代入では didSet が動かないため、保存はされない（撮影専用の一時上書き）。
        if let index = launchArguments.firstIndex(of: "-wmChipStyle"),
           index + 1 < launchArguments.count,
           let forced = MarkerChipStyle(rawValue: launchArguments[index + 1]) {
            style = forced
        }
        chipStyle = style
        breedSort = defaults.string(forKey: Self.breedSortKey)
            .flatMap(BreedSort.init(rawValue:)) ?? .popularity
        // 未保存なら昇順（上から）。register せずに「キーがあればその値、無ければ true」
        breedSortAscending = defaults.object(forKey: Self.breedSortAscendingKey) as? Bool ?? true
    }
}
