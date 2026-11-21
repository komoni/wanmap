import XCTest
@testable import WanMap

/// サーバー表示ID（wan-xxxxxx）の形式テスト。
/// 字面は firestore.rules 側の形式検証と揃える前提のため、
/// ここで崩れたらルール側も見直すこと。
final class DisplayIDTests: XCTestCase {

    func testGeneratedIDsAreAlwaysValid() {
        for _ in 0..<200 {
            let id = DisplayID.generate()
            XCTAssertTrue(DisplayID.isValid(id), "生成したIDが形式を満たしません: \(id)")
        }
    }

    func testValidExamples() {
        XCTAssertTrue(DisplayID.isValid("wan-abc234"))
        XCTAssertTrue(DisplayID.isValid("wan-zzzzzz"))
        XCTAssertTrue(DisplayID.isValid("wan-999999"))
    }

    func testInvalidExamples() {
        XCTAssertFalse(DisplayID.isValid("wan-abc23"), "6文字未満は不可")
        XCTAssertFalse(DisplayID.isValid("wan-abc2345"), "7文字は不可")
        XCTAssertFalse(DisplayID.isValid("wan-ABC234"), "大文字は不可")
        XCTAssertFalse(DisplayID.isValid("wan-ab01cd"), "0と1は字面に無い")
        XCTAssertFalse(DisplayID.isValid("wan-ilo234"), "i・l・oは字面に無い")
        XCTAssertFalse(DisplayID.isValid("abc234"), "接頭辞なしは不可")
        XCTAssertFalse(DisplayID.isValid(""))
    }
}
