import XCTest
import SwiftUI
import UIKit
@testable import WanMap

/// AppearanceStore（見た目の比較案）の検証。
/// テスト専用の UserDefaults スイートを使い、実設定には触らない（hermetic）。
final class AppearanceStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppearanceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefault_初期状態はコーラル案と2段ヘッダー() {
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.buttonVariant, .coral)
        XCTAssertEqual(store.headerLayout, .stacked)
        // 案Aの主ボタン色はコーラル #EE7869
        assertColor(store.primaryColor, hex: 0xEE7869)
    }

    func testVariant_ココア案を選ぶと即保存され主ボタン色がココアになる() {
        let store = AppearanceStore(defaults: defaults)
        store.buttonVariant = .cocoa

        XCTAssertEqual(defaults.string(forKey: "wanmap.appearance.buttonVariant"), "cocoa")
        // 案Bの主ボタン色はココア #533E38
        assertColor(store.primaryColor, hex: 0x533E38)

        let reloaded = AppearanceStore(defaults: defaults)
        XCTAssertEqual(reloaded.buttonVariant, .cocoa)
    }

    func testHeaderLayout_2段を選ぶと即保存され読み戻せる() {
        let store = AppearanceStore(defaults: defaults)
        store.headerLayout = .stacked

        XCTAssertEqual(defaults.string(forKey: "wanmap.appearance.headerLayout"), "stacked")
        let reloaded = AppearanceStore(defaults: defaults)
        XCTAssertEqual(reloaded.headerLayout, .stacked)
    }

    func testFallback_保存値が不明な値なら既定に戻る() {
        defaults.set("no-such-variant", forKey: "wanmap.appearance.buttonVariant")
        defaults.set("no-such-layout", forKey: "wanmap.appearance.headerLayout")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.buttonVariant, .coral)
        XCTAssertEqual(store.headerLayout, .stacked)
    }

    func testLaunchArgument_引数の強制指定が保存値より優先される() {
        // 保存値は既定（コーラル／2段）のまま、撮影用の引数でだけ切り替わる
        let store = AppearanceStore(defaults: defaults,
                                    launchArguments: ["-wmButtonVariant", "cocoa",
                                                      "-wmHeaderLayout", "stacked"])
        XCTAssertEqual(store.buttonVariant, .cocoa)
        XCTAssertEqual(store.headerLayout, .stacked)
        // 引数で強制しても保存値は書き換えない（通常起動に影響を残さない）
        XCTAssertNil(defaults.string(forKey: "wanmap.appearance.buttonVariant"))
        XCTAssertNil(defaults.string(forKey: "wanmap.appearance.headerLayout"))
    }

    func testLaunchArgument_イコール形式と不正値の扱い() {
        let store = AppearanceStore(defaults: defaults,
                                    launchArguments: ["-wmButtonVariant=cocoa"])
        XCTAssertEqual(store.buttonVariant, .cocoa)

        let invalid = AppearanceStore(defaults: defaults,
                                      launchArguments: ["-wmButtonVariant", "purple"])
        XCTAssertEqual(invalid.buttonVariant, .coral)
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
