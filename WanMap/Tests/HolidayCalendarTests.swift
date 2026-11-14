import Foundation
import XCTest
@testable import WanMap

/// 祝日データ（内閣府CSV由来の同梱JSON）が読み込めて、正しい日付に
/// 正しい名前が返ることの回帰テスト（2026-11-14、祝日表示の追加）。
/// JSON の同梱漏れ（project.yml の resources 登録漏れ）もここで検出する。
final class HolidayCalendarTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testNewYear2026() {
        XCTAssertEqual(HolidayCalendar.name(for: date(2026, 1, 1)), "元日")
    }

    func testLaborThanksgiving2026() {
        XCTAssertEqual(HolidayCalendar.name(for: date(2026, 11, 23)), "勤労感謝の日")
    }

    func testOrdinaryDayIsNotHoliday() {
        XCTAssertNil(HolidayCalendar.name(for: date(2026, 11, 14)))
        XCTAssertFalse(HolidayCalendar.isHoliday(date(2026, 11, 14)))
    }
}
