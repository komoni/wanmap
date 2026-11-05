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
