import Foundation
import Observation
import SwiftUI

/// 見た目の比較案の置き場（デザイン・気持ちよさ第一弾）
/// - 主ボタンの配色2案（コーラル／ココア）と、カレンダーヘッダーの
///   レイアウト2案（1段／2段）を切り替えるための設定。
///   どちらも本人がスクリーンショットで見比べて選ぶためのもので、
///   選ばれた方を後に既定化する。恒常機能として残してよい。
/// - 選択値は ThemeStore と同じく UserDefaults に小さく保存する。
/// - スクリーンショット撮影では起動引数で確定的に強制できる：
///   `-wmButtonVariant cocoa` / `-wmHeaderLayout stacked`
///   （引数があれば保存値より優先する。保存値自体は書き換えない）
@Observable
final class AppearanceStore {

    /// 主ボタンの配色案
    enum ButtonVariant: String, CaseIterable {
        /// 案A：現行。主ボタンはコーラル地＋白文字
        case coral
        /// 案B：主ボタンはココア地＋白文字。コーラルは選択・アクセント色として残す
        /// （白文字 on コーラルのコントラスト比 約2.79:1 への対案）
        case cocoa

        var displayName: String {
            switch self {
            case .coral: return "コーラル"
            case .cocoa: return "ココア"
            }
        }
    }

    /// カレンダーヘッダーのレイアウト案
    enum HeaderLayout: String, CaseIterable {
        /// 現行：年月ナビと補助操作を1段に並べる
        case standard
        /// 比較案：補助操作（取り込み・友達・設定）を2段目に落とす
        case stacked

        var displayName: String {
            switch self {
            case .standard: return "1段"
            case .stacked: return "2段"
            }
        }
    }

    static let defaultButtonVariant: ButtonVariant = .coral
    static let defaultHeaderLayout: HeaderLayout = .standard

    private static let buttonVariantKey = "wanmap.appearance.buttonVariant"
    private static let headerLayoutKey = "wanmap.appearance.headerLayout"

    private let defaults: UserDefaults

    /// 選択中の配色案。変更したら即 UserDefaults に保存する
    var buttonVariant: ButtonVariant {
        didSet { defaults.set(buttonVariant.rawValue, forKey: Self.buttonVariantKey) }
    }

    /// 選択中のヘッダーレイアウト。変更したら即 UserDefaults に保存する
    var headerLayout: HeaderLayout {
        didSet { defaults.set(headerLayout.rawValue, forKey: Self.headerLayoutKey) }
    }

    init(defaults: UserDefaults = .standard, launchArguments: [String] = []) {
        self.defaults = defaults
        let savedVariant = defaults.string(forKey: Self.buttonVariantKey)
            .flatMap(ButtonVariant.init(rawValue:)) ?? Self.defaultButtonVariant
        let savedLayout = defaults.string(forKey: Self.headerLayoutKey)
            .flatMap(HeaderLayout.init(rawValue:)) ?? Self.defaultHeaderLayout
        // 起動引数の強制指定があればそちらを優先する（撮影・検証用）
        buttonVariant = Self.argumentValue(named: "-wmButtonVariant", in: launchArguments)
            .flatMap(ButtonVariant.init(rawValue:)) ?? savedVariant
        headerLayout = Self.argumentValue(named: "-wmHeaderLayout", in: launchArguments)
            .flatMap(HeaderLayout.init(rawValue:)) ?? savedLayout
    }

    /// 主ボタンの地色（案で切り替わる唯一の色。文字は常に白）
    var primaryColor: Color {
        switch buttonVariant {
        case .coral: return WanStyle.coral
        case .cocoa: return WanStyle.cocoa
        }
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
}
