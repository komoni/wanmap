import Foundation
import Observation
import SwiftUI

/// テーマ設定の置き場（フェーズO）
/// - ユーザーが選べる配色はここに集約する。今は予定チップの色だけだが、
///   将来アクセントカラー等をユーザー選択に広げる場合は、このクラスに
///   プロパティとプリセットを足し、UserDefaults に保存する形で拡張する
///   （画面側はここの値を読むだけにして、直書きを増やさない）。
/// - 選択値は UserDefaults に小さく保存する（JSONファイル化するほどの
///   データ量ではないため。PlanStore の lastDogName と同じ置き方）。
@Observable
final class ThemeStore {

    /// チップ色プリセット1件分
    struct ChipColorPreset: Identifiable, Equatable {
        let id: String
        let name: String
        let color: Color
    }

    /// 選べるチップ色。先頭（lavender）がデフォルト。
    /// lavender の色値は WanStyle のトークンをそのまま使う（正はそちら）。
    static let chipColorPresets: [ChipColorPreset] = [
        ChipColorPreset(id: "lavender", name: "ラベンダー", color: WanStyle.lavender),
        ChipColorPreset(id: "mint", name: "ミント", color: Color(hex: 0xBDE5D5)),
        ChipColorPreset(id: "peach", name: "ピーチ", color: Color(hex: 0xF7E4CE)),
        ChipColorPreset(id: "sky", name: "スカイ", color: Color(hex: 0xC7DEF0)),
        ChipColorPreset(id: "lemon", name: "レモン", color: Color(hex: 0xF5E7B8)),
    ]

    static let defaultChipColorID = "lavender"
    private static let chipColorIDKey = "wanmap.chipColorID"

    private let defaults: UserDefaults

    /// 選択中のチップ色ID。変更したら即 UserDefaults に保存する
    var chipColorID: String {
        didSet { defaults.set(chipColorID, forKey: Self.chipColorIDKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chipColorID = defaults.string(forKey: Self.chipColorIDKey) ?? Self.defaultChipColorID
    }

    /// 選択中のプリセット。保存値が不明なIDの場合はデフォルトにフォールバックする
    var chipColorPreset: ChipColorPreset {
        Self.chipColorPresets.first { $0.id == chipColorID }
            ?? Self.chipColorPresets.first { $0.id == Self.defaultChipColorID }
            ?? Self.chipColorPresets[0]
    }

    /// 予定チップの背景色（選択中プリセットの色）
    var chipColor: Color { chipColorPreset.color }

    /// チップ色を選ぶ（即変更・即保存。保存ボタンは無い）
    func selectChipColor(id: String) {
        chipColorID = id
    }
}
