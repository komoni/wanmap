import XCTest
import SwiftUI
import UIKit
@testable import WanMap

/// ThemeStore（テーマ設定）の検証。
/// テスト専用の UserDefaults スイートを使い、実設定には触らない（hermetic）。
final class ThemeStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ThemeStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefault_初期状態はラベンダー() {
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.chipColorID, "lavender")
        XCTAssertEqual(store.chipColorPreset.id, "lavender")
        XCTAssertEqual(store.chipColorPreset.name, "ラベンダー")
        // 色そのものもパウダーラベンダー #DCD5F2 であること
        assertColor(store.chipColor, hex: 0xDCD5F2)
    }

    func testPresets_プリセットは5色でデフォルトが先頭() {
        XCTAssertEqual(ThemeStore.chipColorPresets.map(\.id),
                       ["lavender", "mint", "peach", "sky", "lemon"])
        XCTAssertEqual(ThemeStore.chipColorPresets.first?.id, ThemeStore.defaultChipColorID)
    }

    func testSelect_選ぶと即保存され再生成で読み戻せる() {
        let store = ThemeStore(defaults: defaults)
        store.selectChipColor(id: "mint")

        XCTAssertEqual(store.chipColorID, "mint")
        // 保存ボタンなしで UserDefaults に書かれていること（キー名は仕様）
        XCTAssertEqual(defaults.string(forKey: "wanmap.chipColorID"), "mint")

        let reloaded = ThemeStore(defaults: defaults)
        XCTAssertEqual(reloaded.chipColorID, "mint")
        XCTAssertEqual(reloaded.chipColorPreset.name, "ミント")
        assertColor(reloaded.chipColor, hex: 0xBDE5D5)
    }

    func testFallback_保存値が不明なIDならラベンダーになる() {
        defaults.set("no-such-color", forKey: "wanmap.chipColorID")
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.chipColorPreset.id, "lavender")
        assertColor(store.chipColor, hex: 0xDCD5F2)
    }

    // MARK: - 雰囲気テーマ（単位3）

    func testThemeDefault_初期状態はパステルで従来トークンと一致() {
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.appTheme, .pastel)
        assertColor(store.canvasColor, hex: 0xFFF8EF)
        assertColor(store.cardColor, hex: 0xFFFEFC)
        assertColor(store.accentColor, hex: 0xEE7869)
        assertColor(store.saturdayColor, hex: 0x709DC6)
        assertColor(store.dayTextColor, hex: 0x533E38)
    }

    func testThemeSelect_選ぶと即保存され再生成で読み戻せる() {
        let store = ThemeStore(defaults: defaults)
        store.appTheme = .dark

        XCTAssertEqual(defaults.string(forKey: "wanmap.appTheme"), "dark")
        let reloaded = ThemeStore(defaults: defaults)
        XCTAssertEqual(reloaded.appTheme, .dark)
        // ダークのパレット（地は暗く、本文は明るく、アクセントは淡いコーラル）
        assertColor(reloaded.canvasColor, hex: 0x26211F)
        assertColor(reloaded.cardColor, hex: 0x3A3330)
        assertColor(reloaded.accentColor, hex: 0xF0997F)
        assertColor(reloaded.dayTextColor, hex: 0xF3EAE2)
        // ダークではヘッダーのショートカットアイコンは白（差し色は沈んで見えるため）
        assertColor(reloaded.headerIconColor, hex: 0xFFFFFF)
    }

    func testThemeCool_クールのパレット() {
        let store = ThemeStore(defaults: defaults)
        store.appTheme = .cool
        assertColor(store.canvasColor, hex: 0xE9EEF3)
        assertColor(store.cardColor, hex: 0xFFFFFF)
        assertColor(store.accentColor, hex: 0x2F6DB3)
        assertColor(store.dayTextColor, hex: 0x2E4A5E)
    }

    func testThemeFallback_保存値が不明なテーマならパステルになる() {
        defaults.set("no-such-theme", forKey: "wanmap.appTheme")
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.appTheme, .pastel)
    }

    func testThemeLaunchArgument_起動引数が保存値より優先され保存値は書き換わらない() {
        let store = ThemeStore(defaults: defaults, launchArguments: ["-wmTheme", "dark"])
        XCTAssertEqual(store.appTheme, .dark)
        // 引数は表示だけの強制で、保存値（未保存＝既定パステル）は変わらない
        let reloaded = ThemeStore(defaults: defaults)
        XCTAssertEqual(reloaded.appTheme, .pastel)
    }

    // MARK: - ヘルパー

    private func assertColor(_ color: Color, hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a),
                      "色のRGB成分を取り出せるはず", file: file, line: line)
        XCTAssertEqual(r, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(g, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(b, CGFloat(hex & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
    }
}
