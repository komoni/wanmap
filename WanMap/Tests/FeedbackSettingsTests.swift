import XCTest
@testable import WanMap

/// FeedbackSettings（音と触覚の設定）の検証。
/// テスト専用の UserDefaults スイートを使い、実設定には触らない（hermetic）。
final class FeedbackSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FeedbackSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefault_未保存なら効果音も触覚もON() {
        // 既定ONは本人の決定。bool(forKey:) の暗黙の false に引きずられないこと
        let settings = FeedbackSettings(defaults: defaults)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertTrue(settings.hapticsEnabled)
    }

    func testToggle_OFFにすると即保存され読み戻せる() {
        let settings = FeedbackSettings(defaults: defaults)
        settings.soundEnabled = false
        settings.hapticsEnabled = false

        XCTAssertEqual(defaults.bool(forKey: "wanmap.feedback.soundEnabled"), false)
        XCTAssertEqual(defaults.bool(forKey: "wanmap.feedback.hapticsEnabled"), false)

        let reloaded = FeedbackSettings(defaults: defaults)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertFalse(reloaded.hapticsEnabled)
    }

    func testToggle_音と触覚は独立に保存される() {
        let settings = FeedbackSettings(defaults: defaults)
        settings.soundEnabled = false

        let reloaded = FeedbackSettings(defaults: defaults)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertTrue(reloaded.hapticsEnabled)
    }
}
