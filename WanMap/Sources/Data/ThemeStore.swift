import Foundation
import Observation
import SwiftUI

/// テーマ設定の置き場（フェーズO）
/// - ユーザーが選べる配色はここに集約する。予定チップの色（フェーズO）に加え、
///   画面全体の雰囲気プリセット「テーマ」（パステル／ダーク／クール）を置く
///   （設定・カレンダーバッチ単位3、2026-11-12）。テーマの適用範囲は
///   カレンダー画面（地・カード・アクセント・日付文字）。地図など他の画面は
///   対象外で、WanStyle の従来トークンのまま。
/// - 選択値は UserDefaults に小さく保存する（JSONファイル化するほどの
///   データ量ではないため。PlanStore の lastDogName と同じ置き方）。
/// - スクリーンショット撮影では起動引数でテーマを強制できる：
///   `-wmTheme dark`（引数があれば保存値より優先。保存値自体は書き換えない）
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

    /// 画面全体の雰囲気プリセット
    enum AppTheme: String, CaseIterable {
        /// 現行のパステル（ミルク地＋コーラル）。既定
        case pastel
        /// 濃いココア〜チャコール基調のダーク
        case dark
        /// 青灰基調のクール
        case cool

        var displayName: String {
            switch self {
            case .pastel: return "パステル"
            case .dark: return "ダーク"
            case .cool: return "クール"
            }
        }
    }

    static let defaultAppTheme: AppTheme = .pastel
    private static let appThemeKey = "wanmap.appTheme"

    private let defaults: UserDefaults

    /// 選択中のチップ色ID。変更したら即 UserDefaults に保存する
    var chipColorID: String {
        didSet { defaults.set(chipColorID, forKey: Self.chipColorIDKey) }
    }

    /// 選択中のテーマ。変更したら即 UserDefaults に保存する
    var appTheme: AppTheme {
        didSet { defaults.set(appTheme.rawValue, forKey: Self.appThemeKey) }
    }

    init(defaults: UserDefaults = .standard, launchArguments: [String] = []) {
        self.defaults = defaults
        chipColorID = defaults.string(forKey: Self.chipColorIDKey) ?? Self.defaultChipColorID
        let savedTheme = defaults.string(forKey: Self.appThemeKey)
            .flatMap(AppTheme.init(rawValue:)) ?? Self.defaultAppTheme
        // 起動引数の強制指定があればそちらを優先する（撮影・検証用）
        appTheme = Self.argumentValue(named: "-wmTheme", in: launchArguments)
            .flatMap(AppTheme.init(rawValue:)) ?? savedTheme
    }

    /// 起動引数 `-name value` または `-name=value` の値を取る
    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        for (index, arg) in arguments.enumerated() {
            if arg == name, index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if arg.hasPrefix(name + "=") {
                return String(arg.dropFirst(name.count + 1))
            }
        }
        return nil
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

    // MARK: - テーマのパレット（カレンダー画面が読む色）

    /// 地色（画面の背景）
    var canvasColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.canvas
        case .dark: return Color(hex: 0x26211F)
        case .cool: return Color(hex: 0xE9EEF3)
        }
    }

    /// カード面（日セル・ミニカレンダー・ヘッダーの帯）
    var cardColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.card
        case .dark: return Color(hex: 0x3A3330)
        case .cool: return Color(hex: 0xFFFFFF)
        }
    }

    /// アクセント（今日・日曜・ヘッダーのアイコン・主ボタン）
    var accentColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.coral
        case .dark: return Color(hex: 0xF0997F)
        case .cool: return Color(hex: 0x2F6DB3)
        }
    }

    /// ヘッダーのショートカットアイコン色（月送り・取り込み・友達・設定）。
    /// ダークでは差し色（淡いコーラル）が暗い地で黄色っぽく沈んで見えにくいため
    /// 白にする（2026-11-13、本人の指摘）
    var headerIconColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.coral
        case .dark: return Color(hex: 0xFFFFFF)
        case .cool: return Color(hex: 0x2F6DB3)
        }
    }

    /// 土曜の色
    var saturdayColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.saturday
        case .dark: return Color(hex: 0x93BEE3)
        case .cool: return Color(hex: 0x6E9CC0)
        }
    }

    /// 本文色（日付の数字など。ココアの役割）
    var dayTextColor: Color {
        switch appTheme {
        case .pastel: return WanStyle.cocoa
        case .dark: return Color(hex: 0xF3EAE2)
        case .cool: return Color(hex: 0x2E4A5E)
        }
    }

    /// 補助文字色（曜日見出しの平日など。Color.secondary の役割）
    var subTextColor: Color {
        switch appTheme {
        case .pastel: return Color.secondary
        case .dark: return Color(hex: 0xB9ACA2)
        case .cool: return Color(hex: 0x5E7688)
        }
    }
}
