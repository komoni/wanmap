import XCTest
@testable import WanMap

/// UserFeedbackService の本文バリデーション（単位2-6）。
/// ルール側の制約（1〜2000文字）とアプリ側の正規化が一致していることが要る。
final class UserFeedbackServiceTests: XCTestCase {

    func testNormalizedBodyは前後の空白を除く() {
        XCTAssertEqual(UserFeedbackService.normalizedBody("  要望です \n"), "要望です")
        XCTAssertEqual(UserFeedbackService.normalizedBody("そのまま"), "そのまま")
    }

    func testNormalizedBodyは空と上限超えを弾く() {
        XCTAssertNil(UserFeedbackService.normalizedBody(""))
        XCTAssertNil(UserFeedbackService.normalizedBody("  \n "))
        XCTAssertNil(UserFeedbackService.normalizedBody(String(repeating: "あ", count: 2001)))
        XCTAssertNotNil(UserFeedbackService.normalizedBody(String(repeating: "あ", count: 2000)))
    }
}
