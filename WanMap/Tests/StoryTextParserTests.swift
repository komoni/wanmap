import XCTest
@testable import WanMap

/// StoryTextParser の検証。基準日を 2026-11-05（木）に固定して、
/// 日付表現・時間帯・場所照合・確度の解釈ルールが仕様どおりであることを守る。
final class StoryTextParserTests: XCTestCase {
    private let cal = StoryTextParser.calendar

    /// 基準日（投稿日）：2026-11-05（木）
    private var base: Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 5))!
    }

    private let dogWith = makeFacility(name: "ドッグウィズ")

    private func parse(_ text: String,
                       facilities: [Facility]? = nil,
                       userPlaces: [UserPlace] = []) -> [StoryTextDraft] {
        StoryTextParser.parse(text: text, baseDate: base,
                              facilities: facilities ?? [dogWith], userPlaces: userPlaces)
    }

    private func assertDate(_ draft: StoryTextDraft, _ year: Int, _ month: Int, _ day: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        let c = cal.dateComponents([.year, .month, .day], from: draft.date)
        XCTAssertEqual(c.year, year, "年が想定と違います", file: file, line: line)
        XCTAssertEqual(c.month, month, "月が想定と違います", file: file, line: line)
        XCTAssertEqual(c.day, day, "日が想定と違います", file: file, line: line)
    }

    // MARK: - 日付の解釈

    func testParse_明日は基準日の翌日になる() {
        let drafts = parse("明日ドッグウィズに行く")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 6)
        XCTAssertEqual(drafts[0].placeName, "ドッグウィズ")
    }

    func testParse_明後日は基準日の2日後になる() {
        let drafts = parse("明後日ドッグウィズに行く")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 7)
    }

    func testParse_月日指定は同年のその日になる() {
        let drafts = parse("11月8日はドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 8)
    }

    func testParse_過ぎた月日は翌年に倒れる() {
        // 11月2日は基準日（11月5日）より前なので、予定としては翌年として解釈する
        let drafts = parse("11月2日ドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2027, 11, 2)
    }

    func testParse_日にちだけの指定は今月のその日になる() {
        let drafts = parse("15日にドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 15)
    }

    func testParse_今週末はその週の土曜日になる() {
        // 基準日は木曜。その週の土曜は 11月7日
        let drafts = parse("今週末ドッグウィズに行く")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 7)
    }

    func testParse_今週の曜日指定は直近のその曜日になる() {
        let drafts = parse("今週の金曜はドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 6)
    }

    func testParse_単独の曜日指定も直近のその曜日になる() {
        let drafts = parse("土曜にドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 7)
    }

    func testParse_来週の曜日は来週の日になる() {
        // 基準日の週の土曜は11月7日なので、「来週の土曜」は11月14日
        let drafts = parse("来週の土曜はドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 14)
    }

    func testParse_日付表現が無ければ基準日を仮置きする() {
        // エラーにはせず、投稿日（基準日）をそのまま使う（決定済み仕様）
        let drafts = parse("ドッグウィズに行く")
        XCTAssertEqual(drafts.count, 1)
        assertDate(drafts[0], 2026, 11, 5)
    }

    // MARK: - 時間帯の解釈

    func testParse_夕方は夜の時間帯に寄せる() {
        let drafts = parse("明日の夕方ドッグウィズ")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].timeBand, .night)
        assertDate(drafts[0], 2026, 11, 6)
    }

    func testParse_朝は朝の時間帯になる() {
        let drafts = parse("明日の朝ドッグウィズ")
        XCTAssertEqual(drafts[0].timeBand, .morning)
    }

    func testParse_時間帯の語が無ければ終日になる() {
        let drafts = parse("明日ドッグウィズ")
        XCTAssertEqual(drafts[0].timeBand, .allDay)
    }

    // MARK: - 場所の照合（正規化）

    func testParse_施設名は小文字とアポストロフィ違いでも一致する() {
        // 過去に「b」で検索しても出なかった表記ゆれ問題の回帰防止（パーサー側）
        let bamboos = makeFacility(name: "BamBoo's", displayName: "BamBoo's（バンブーズ）")
        let drafts = parse("明日、bamboo'sに行く", facilities: [bamboos])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].placeName, "BamBoo's")
        XCTAssertEqual(drafts[0].facility?.name, "BamBoo's")
    }

    func testParse_施設名は全角英字でも一致する() {
        let bamboos = makeFacility(name: "BamBoo's", displayName: "BamBoo's（バンブーズ）")
        let drafts = parse("明日、ＢａｍＢｏｏ＇ｓに行く", facilities: [bamboos])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].facility?.name, "BamBoo's")
    }

    func testParse_自分の場所が公式施設より優先して先に来る() {
        let mine = makeUserPlace(name: "ドッグウィズ裏の広場")
        let drafts = parse("明日ドッグウィズ裏の広場で遊ぶ", userPlaces: [mine])
        XCTAssertEqual(drafts.count, 2, "自分の場所と公式施設の両方が候補に出る想定")
        XCTAssertEqual(drafts[0].userPlace?.name, "ドッグウィズ裏の広場")
        XCTAssertNil(drafts[0].facility)
        XCTAssertEqual(drafts[1].facility?.name, "ドッグウィズ")
    }

    func testParse_場所が1つも一致しなければ場所未定の下書きが1件返る() {
        let drafts = parse("明日の朝どこか行きたい")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].placeName, "")
        XCTAssertNil(drafts[0].facility)
        XCTAssertNil(drafts[0].userPlace)
        // 日付・時間帯だけは拾えていること
        assertDate(drafts[0], 2026, 11, 6)
        XCTAssertEqual(drafts[0].timeBand, .morning)
    }

    // MARK: - 確度

    func testParse_確度の上限は中で高は存在しない() {
        XCTAssertEqual(Set(InferenceConfidence.allCases.map(\.rawValue)), ["中", "低"])
    }

    func testParse_場所と日付が両方取れれば確度は中になる() {
        let drafts = parse("明日ドッグウィズに行く")
        XCTAssertEqual(drafts[0].confidence, .medium)
    }

    func testParse_日付表現が無ければ場所が取れても確度は低になる() {
        let drafts = parse("ドッグウィズに行く")
        XCTAssertEqual(drafts[0].confidence, .low)
    }

    func testParse_場所が取れなければ確度は低になる() {
        let drafts = parse("明日どこか行きたい")
        XCTAssertEqual(drafts[0].confidence, .low)
    }
}
