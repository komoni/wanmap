import XCTest
@testable import WanMap

/// RecurrenceGenerator（繰り返し開催日の純粋関数）の検証。
/// カレンダーとタイムゾーンを固定し、月末・年またぎ・第5曜日などの
/// 暦の境界ケースを決定的に確かめる。
final class RecurrenceGeneratorTests: XCTestCase {

    private var tokyo: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func labels(_ dates: [Date], calendar: Calendar) -> [String] {
        dates.map { date in
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(c.year!)/\(c.month!)/\(c.day!)"
        }
    }

    /// 種類と開始日から規則を導出して生成する（フォームと同じ経路）
    private func generate(kind: RecurrenceKind, start: Date, count: Int = 3,
                          calendar: Calendar) -> [Date]? {
        let rule = RecurrenceRule(kind: kind, startDate: start, calendar: calendar)
        return RecurrenceGenerator.dates(rule: rule, start: start, count: count, calendar: calendar)
    }

    // MARK: - 毎週

    func testWeekly_同じ曜日で7日ずつ進む() {
        let cal = tokyo
        let start = makeDate(2026, 11, 1, calendar: cal)  // 日曜
        let dates = generate(kind: .weekly, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/11/1"], ["2026/11/8"], ["2026/11/15"]])
    }

    func testWeekly_年をまたぐ() {
        let cal = tokyo
        let start = makeDate(2026, 12, 27, calendar: cal)  // 日曜
        let dates = generate(kind: .weekly, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/12/27"], ["2027/1/3"], ["2027/1/10"]])
    }

    func testWeekly_夏時間をまたいでも曜日が維持される() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = makeDate(2026, 3, 1, calendar: cal)  // 日曜。DST開始（3/8）をまたぐ
        let dates = generate(kind: .weekly, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/3/1"], ["2026/3/8"], ["2026/3/15"]])
        XCTAssertEqual(dates?.map { cal.component(.weekday, from: $0) }, [1, 1, 1])
    }

    // MARK: - 毎月同日

    func testMonthlyDay_月末は末日に寄せ翌月は元の日に戻る() {
        let cal = tokyo
        let start = makeDate(2027, 1, 31, calendar: cal)
        let dates = generate(kind: .monthlyDay, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2027/1/31"], ["2027/2/28"], ["2027/3/31"]])
    }

    func testMonthlyDay_30日指定でも2月だけ末日になり3月は30日に戻る() {
        let cal = tokyo
        let start = makeDate(2027, 1, 30, calendar: cal)
        let dates = generate(kind: .monthlyDay, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2027/1/30"], ["2027/2/28"], ["2027/3/30"]])
    }

    func testMonthlyDay_うるう年は2月29日になる() {
        let cal = tokyo
        let start = makeDate(2028, 1, 31, calendar: cal)
        let dates = generate(kind: .monthlyDay, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2028/1/31"], ["2028/2/29"], ["2028/3/31"]])
    }

    func testMonthlyDay_月末でない日は重ねてもずれない() {
        let cal = tokyo
        let start = makeDate(2027, 1, 15, calendar: cal)
        let dates = generate(kind: .monthlyDay, start: start, count: 6, calendar: cal)
        XCTAssertEqual(dates?.map { cal.component(.day, from: $0) }, [15, 15, 15, 15, 15, 15])
    }

    // MARK: - 毎月第○曜日

    func testMonthlyOrdinal_第1日曜() {
        let cal = tokyo
        let start = makeDate(2026, 11, 1, calendar: cal)  // 第1日曜
        let dates = generate(kind: .monthlyOrdinalWeekday, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/11/1"], ["2026/12/6"], ["2027/1/3"]])
    }

    func testMonthlyOrdinal_第2火曜() {
        let cal = tokyo
        let start = makeDate(2026, 11, 10, calendar: cal)  // 第2火曜
        let dates = generate(kind: .monthlyOrdinalWeekday, start: start, calendar: cal)
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/11/10"], ["2026/12/8"], ["2027/1/12"]])
    }

    func testMonthlyOrdinal_第5曜日がない月はその月の最後の同じ曜日になる() {
        let cal = tokyo
        let start = makeDate(2026, 11, 29, calendar: cal)  // 第5日曜
        let dates = generate(kind: .monthlyOrdinalWeekday, start: start, calendar: cal)
        // 2026年12月は日曜が4回しかないので最終日曜（27日）に倒れる。翌1月は第5日曜（31日）に戻る
        XCTAssertEqual(dates.map { labels([$0], calendar: cal) },
                       [["2026/11/29"], ["2026/12/27"], ["2027/1/31"]])
    }

    // MARK: - 回数

    func testCounts_各種類で指定回数ぶん生成される() {
        let cal = tokyo
        let cases: [(RecurrenceKind, Date)] = [
            (.weekly, makeDate(2026, 11, 1, calendar: cal)),
            (.monthlyDay, makeDate(2026, 11, 15, calendar: cal)),
            (.monthlyOrdinalWeekday, makeDate(2026, 11, 1, calendar: cal)),
        ]
        for (kind, start) in cases {
            for count in [6, 12] {
                let dates = generate(kind: kind, start: start, count: count, calendar: cal)
                XCTAssertEqual(dates?.count, count, "\(kind) ×\(count) の生成件数が合いません")
            }
        }
        // 毎週×12 の最終回は初回＋77日
        let weekly = generate(kind: .weekly, start: makeDate(2026, 11, 1, calendar: cal),
                              count: 12, calendar: cal)
        XCTAssertEqual(weekly.flatMap { labels([$0], calendar: cal).first }, "2027/1/17")
    }

    // MARK: - 不正条件の拒否

    func testInvalid_選べない回数は拒否される() {
        let cal = tokyo
        let start = makeDate(2026, 11, 1, calendar: cal)
        for count in [0, 1, 2, 4, 5, 13] {
            XCTAssertNil(generate(kind: .weekly, start: start, count: count, calendar: cal),
                         "回数 \(count) が拒否されませんでした")
        }
    }

    func testInvalid_毎週で曜日が開始日と違う規則は拒否される() {
        let cal = tokyo
        let start = makeDate(2026, 11, 1, calendar: cal)  // 日曜（weekday=1）
        let rule = RecurrenceRule(kind: .weekly, weekday: 2)
        XCTAssertNil(RecurrenceGenerator.dates(rule: rule, start: start, count: 3, calendar: cal))
    }

    func testInvalid_毎月同日で日が範囲外・開始日と違う規則は拒否される() {
        let cal = tokyo
        let start = makeDate(2027, 1, 15, calendar: cal)
        let outOfRange = RecurrenceRule(kind: .monthlyDay, dayOfMonth: 32)
        XCTAssertNil(RecurrenceGenerator.dates(rule: outOfRange, start: start, count: 3, calendar: cal))
        let mismatch = RecurrenceRule(kind: .monthlyDay, dayOfMonth: 16)
        XCTAssertNil(RecurrenceGenerator.dates(rule: mismatch, start: start, count: 3, calendar: cal))
    }

    func testInvalid_第0曜日・第6曜日・曜日8は拒否される() {
        let cal = tokyo
        let start = makeDate(2026, 11, 1, calendar: cal)  // 第1日曜
        let zeroOrdinal = RecurrenceRule(kind: .monthlyOrdinalWeekday, weekday: 1, ordinal: 0)
        XCTAssertNil(RecurrenceGenerator.dates(rule: zeroOrdinal, start: start, count: 3, calendar: cal))
        let sixthOrdinal = RecurrenceRule(kind: .monthlyOrdinalWeekday, weekday: 1, ordinal: 6)
        XCTAssertNil(RecurrenceGenerator.dates(rule: sixthOrdinal, start: start, count: 3, calendar: cal))
        let weekday8 = RecurrenceRule(kind: .monthlyOrdinalWeekday, weekday: 8, ordinal: 1)
        XCTAssertNil(RecurrenceGenerator.dates(rule: weekday8, start: start, count: 3, calendar: cal))
    }
}
