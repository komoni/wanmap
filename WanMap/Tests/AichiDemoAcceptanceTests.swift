import XCTest
@testable import WanMap

/// 愛ハス定例デモの受入条件（REVIEW_PHASE_Q_TRIAGE.md「デモ受入条件」）の検証。
///
/// 前提は受入条件どおり：固定日付・Gregorian・Asia/Tokyo（WanMapCalendar.shared）、
/// 隔離した永続保存先（一時ファイル）。通常データには触れない。
/// 画面表示の確認は、ビューが実際に消費する PlanStore の API
/// （activePlans の日別グルーピング＝月表示・年表示、plans(on:)＝日別一覧、
/// activePlans＋座標＋同日判定＝地図）で担保し、実画面での操作・再起動の
/// 通し確認は UI フロー（WanMapFlowTests のフロー7）が担う。
final class AichiDemoAcceptanceTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    /// アプリ全体で共用する暦（Gregorian／Asia/Tokyo）で固定日付を作る
    private var cal: Calendar { WanMapCalendar.shared }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func label(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)/\(c.month!)/\(c.day!)"
    }

    /// ドッグウィズの座標（SeedData と同じ値）
    private let dogWith = (lat: 35.1649375, lng: 137.08455)
    /// SKドッグランの座標（SeedData と同じ値。別シリーズ用）
    private let skRun = (lat: 34.7921028, lng: 137.0232936)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wanmap-aichi-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("plans.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 再読込をまたいでも比較できるよう、主要項目だけを取り出した署名。
    /// Plan 全体の等値比較は createdAt の小数秒が保存形式（ISO8601・秒まで）で
    /// 落ちるため、再読込後の照合には使わない。
    private func signature(_ plans: [Plan]) -> [String] {
        plans.map {
            "\($0.id)|\($0.date.timeIntervalSince1970)|\($0.placeName)"
                + "| lat=\($0.latitude ?? -1) lng=\($0.longitude ?? -1)"
                + "| \($0.timeBand.rawValue)|\($0.dogName ?? "")|idx=\($0.occurrenceIndex ?? -1)"
        }
    }

    /// 愛ハス定例：第1日曜日×3回（初回 2026-12-06、場所はドッグウィズ）を登録する
    private func registerAichiSeries(in store: PlanStore) throws -> RecurrenceSeries {
        let start = day(2026, 12, 6)
        let rule = RecurrenceRule(kind: .monthlyOrdinalWeekday, startDate: start, calendar: cal)
        var template = makePlan(placeName: "ドッグウィズ", date: start)
        template.dogName = "ハス太"
        template.latitude = dogWith.lat
        template.longitude = dogWith.lng
        template.timeBand = .morning
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: cal)
        return try XCTUnwrap(series, "愛ハス定例シリーズが登録できませんでした")
    }

    // MARK: - 受入条件1：固定日付で第1日曜日×3回を新規登録できる

    func test_第1日曜日3回が固定日付で登録できる() throws {
        let store = PlanStore(fileURL: fileURL)
        let series = try registerAichiSeries(in: store)

        XCTAssertEqual(series.rule.kind, .monthlyOrdinalWeekday)
        XCTAssertEqual(series.rule.ordinal, 1)
        XCTAssertEqual(series.rule.weekday, 1, "曜日は日曜（1）のはず")
        XCTAssertEqual(series.occurrenceCount, 3)

        let children = store.occurrences(of: series.id)
        XCTAssertEqual(children.map { label($0.date) },
                       ["2026/12/6", "2027/1/3", "2027/2/7"])
        XCTAssertEqual(children.map(\.occurrenceIndex), [0, 1, 2])
        for child in children {
            XCTAssertEqual(child.seriesID, series.id)
            XCTAssertEqual(child.originalDate, child.date, "当初日は開催日と一致するはず")
            XCTAssertEqual(child.placeName, "ドッグウィズ")
            XCTAssertEqual(child.latitude, dogWith.lat)
            XCTAssertEqual(child.longitude, dogWith.lng)
            XCTAssertFalse(child.isSeriesException)
            // 第1日曜日であること（日曜かつ日が1〜7）
            XCTAssertEqual(cal.component(.weekday, from: child.date), 1)
            XCTAssertLessThanOrEqual(cal.component(.day, from: child.date), 7)
        }
        XCTAssertEqual(Set(children.map(\.id)).count, 3, "各回のIDは別々のはず")
    }

    // MARK: - 受入条件2（表示）：月・年・日別で3回分が見える

    func test_月年日別の表示用クエリで3回分が見える() throws {
        let store = PlanStore(fileURL: fileURL)
        _ = try registerAichiSeries(in: store)

        // 月表示・年表示は CalendarView が activePlans を日別に束ねて描く。
        // その束ね方を再現し、3回分が3つの月に印として出ることを確かめる。
        let plansByDay = Dictionary(grouping: store.activePlans) { cal.startOfDay(for: $0.date) }
        let expectedDays = [day(2026, 12, 6), day(2027, 1, 3), day(2027, 2, 7)]
        for expected in expectedDays {
            XCTAssertEqual(plansByDay[expected]?.count, 1,
                           "\(label(expected)) に予定の印が付くはず")
        }
        let markedMonths = Set(plansByDay.keys.map {
            "\(cal.component(.year, from: $0))/\(cal.component(.month, from: $0))"
        })
        XCTAssertEqual(markedMonths, ["2026/12", "2027/1", "2027/2"],
                       "月表示3か月分（2026年12月・2027年1月・2月）に広がるはず")
        // 年表示（2027年）でも1月・2月の2回に印が付く
        let markedIn2027 = plansByDay.keys.filter { cal.component(.year, from: $0) == 2027 }
        XCTAssertEqual(Set(markedIn2027.map { label($0) }), ["2027/1/3", "2027/2/7"])

        // 日別一覧（DayPlansView は plans(on:) を使う）
        for expected in expectedDays {
            let dayPlans = store.plans(on: expected)
            XCTAssertEqual(dayPlans.count, 1, "\(label(expected)) の日別一覧に1件出るはず")
            XCTAssertEqual(dayPlans.first?.placeName, "ドッグウィズ")
        }
    }

    // MARK: - 受入条件2（変更）：1回を別日へ変更してもID・元日付と他回は不変

    func test_1回だけ別日へ変更してもIDと元日付が安定し他回は不変() throws {
        let store = PlanStore(fileURL: fileURL)
        let series = try registerAichiSeries(in: store)
        let before = store.occurrences(of: series.id)
        XCTAssertEqual(before.count, 3)

        // 2027-01-03 の回だけを 2027-01-10（翌週の日曜）へ移し、時間帯も変える
        var moved = before[1]
        moved.date = day(2027, 1, 10)
        moved.timeBand = .night
        XCTAssertTrue(store.updateOccurrence(moved))

        let after = store.occurrences(of: series.id)
        XCTAssertEqual(after.count, 3)
        // 変更した回：IDと元日付は安定し、例外フラグが立つ
        XCTAssertEqual(after[1].id, before[1].id)
        XCTAssertEqual(after[1].originalDate, day(2027, 1, 3), "元日付は当初の開催日のままのはず")
        XCTAssertEqual(after[1].date, day(2027, 1, 10))
        XCTAssertEqual(after[1].timeBand, .night)
        XCTAssertTrue(after[1].isSeriesException)
        // 他の回と親は完全に不変
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[2], before[2])
        XCTAssertEqual(store.series.first?.rule, series.rule)
        XCTAssertEqual(store.series.first?.startDate, series.startDate)
        XCTAssertEqual(store.series.first?.template, series.template)
        // 日別一覧でも移っている
        XCTAssertTrue(store.plans(on: day(2027, 1, 3)).isEmpty)
        XCTAssertEqual(store.plans(on: day(2027, 1, 10)).map(\.id), [before[1].id])
    }

    // MARK: - 受入条件3：変更・削除が地図側にも反映される

    func test_変更と削除が地図の表示条件にも反映される() throws {
        let store = PlanStore(fileURL: fileURL)
        let series = try registerAichiSeries(in: store)

        // DogMapView.mapPlans の条件（座標あり・「今ここ」以外・選択日と同日）を再現する
        func mapVisible(on day: Date) -> [Plan] {
            store.activePlans.filter {
                $0.coordinate != nil && !$0.isPresence && cal.isDate($0.date, inSameDayAs: day)
            }
        }
        XCTAssertEqual(mapVisible(on: day(2026, 12, 6)).count, 1)
        XCTAssertEqual(mapVisible(on: day(2027, 1, 3)).count, 1)
        XCTAssertEqual(mapVisible(on: day(2027, 2, 7)).count, 1)

        // 1回を別日へ変更 → 地図でも旧日から消え、新しい日に出る
        var moved = store.occurrences(of: series.id)[1]
        moved.date = day(2027, 1, 10)
        XCTAssertTrue(store.updateOccurrence(moved))
        XCTAssertTrue(mapVisible(on: day(2027, 1, 3)).isEmpty)
        XCTAssertEqual(mapVisible(on: day(2027, 1, 10)).map(\.id), [moved.id])

        // その回を削除 → 地図からも消え、他の回は残る
        XCTAssertTrue(store.removeOccurrence(moved))
        XCTAssertTrue(mapVisible(on: day(2027, 1, 10)).isEmpty)
        XCTAssertEqual(mapVisible(on: day(2026, 12, 6)).count, 1)
        XCTAssertEqual(mapVisible(on: day(2027, 2, 7)).count, 1)
    }

    // MARK: - 受入条件4：再起動相当の再読込でも登録・変更が保持される

    func test_再読込でも登録と変更が保持される() throws {
        let store = PlanStore(fileURL: fileURL)
        let series = try registerAichiSeries(in: store)
        var moved = store.occurrences(of: series.id)[1]
        moved.date = day(2027, 1, 10)
        moved.timeBand = .night
        XCTAssertTrue(store.updateOccurrence(moved))
        let expectedIDs = Set(store.occurrences(of: series.id).map(\.id))

        // 同じ保存先から作り直す＝アプリ再起動相当（シードでの上書きはしない）
        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertFalse(reloaded.loadFailed)
        XCTAssertEqual(reloaded.series.count, 1)
        XCTAssertEqual(reloaded.series.first?.id, series.id, "親のIDが同じはず")
        let children = reloaded.occurrences(of: series.id)
        XCTAssertEqual(Set(children.map(\.id)), expectedIDs, "子IDが同じ集合のはず")
        XCTAssertEqual(children.map { label($0.date) },
                       ["2026/12/6", "2027/1/10", "2027/2/7"])
        XCTAssertEqual(children[1].originalDate, day(2027, 1, 3))
        XCTAssertEqual(children[1].timeBand, .night)
        XCTAssertTrue(children[1].isSeriesException)
    }

    // MARK: - 受入条件5a：個別削除が再読込でも復活しない

    func test_削除した回は再読込でも復活しない() throws {
        let store = PlanStore(fileURL: fileURL)
        let series = try registerAichiSeries(in: store)
        let target = store.occurrences(of: series.id)[1]
        XCTAssertTrue(store.removeOccurrence(target))

        let reloaded = PlanStore(fileURL: fileURL)
        let children = reloaded.occurrences(of: series.id)
        XCTAssertEqual(children.map { label($0.date) }, ["2026/12/6", "2027/2/7"])
        XCTAssertFalse(children.contains { $0.id == target.id }, "削除した回が復活してはいけない")
        XCTAssertTrue(reloaded.plans(on: day(2027, 1, 3)).isEmpty)
        XCTAssertEqual(reloaded.series.count, 1, "回が残っている間は親も残るはず")

        // 残りの回を全部消すと親も消え、再読込でも戻らない
        for child in children {
            XCTAssertTrue(reloaded.removeOccurrence(child))
        }
        let final = PlanStore(fileURL: fileURL)
        XCTAssertTrue(final.series.isEmpty)
        XCTAssertTrue(final.plans.isEmpty)
    }

    // MARK: - 受入条件5b：シリーズ全体の編集・削除が別シリーズに影響しない

    func test_シリーズ編集と削除が別シリーズに影響しない() throws {
        let store = PlanStore(fileURL: fileURL)
        let aichi = try registerAichiSeries(in: store)

        // 別シリーズ：2026-11-01（日曜）開始の毎週×3回、SKドッグラン
        let weeklyStart = day(2026, 11, 1)
        let weeklyRule = RecurrenceRule(kind: .weekly, startDate: weeklyStart, calendar: cal)
        var weeklyTemplate = makePlan(placeName: "SKドッグラン", date: weeklyStart)
        weeklyTemplate.dogName = "コタロウ"
        weeklyTemplate.latitude = skRun.lat
        weeklyTemplate.longitude = skRun.lng
        weeklyTemplate.timeBand = .noon
        let weekly = store.addSeries(rule: weeklyRule, occurrenceCount: 3,
                                     templatePlan: weeklyTemplate, calendar: cal)
        XCTAssertNotNil(weekly)
        guard let weekly else { return }
        let weeklyBefore = store.occurrences(of: weekly.id)

        // 愛ハス側だけ全体編集（時間帯と場所をまとめて変更）
        var newTemplate = aichi.template
        newTemplate.timeBand = .night
        newTemplate.placeName = "別の場所"
        newTemplate.latitude = 35.0
        newTemplate.longitude = 137.0
        XCTAssertTrue(store.updateSeriesContent(seriesID: aichi.id, newTemplate: newTemplate))
        XCTAssertTrue(store.occurrences(of: aichi.id).allSatisfy {
            $0.timeBand == .night && $0.placeName == "別の場所"
                && $0.latitude == 35.0 && $0.longitude == 137.0
        })
        XCTAssertEqual(store.occurrences(of: weekly.id), weeklyBefore,
                       "全体編集が別シリーズの回へ及んではいけない")
        XCTAssertEqual(store.seriesFor(weeklyBefore[0])?.template, weekly.template)

        // 再読込しても別シリーズは不変のまま（署名で照合する）
        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertEqual(signature(reloaded.occurrences(of: weekly.id)), signature(weeklyBefore))

        // 愛ハス側だけ全体削除 → 別シリーズはメモリ上でも再読込でも残る
        XCTAssertTrue(reloaded.removeSeries(id: aichi.id))
        XCTAssertTrue(reloaded.occurrences(of: aichi.id).isEmpty)
        XCTAssertEqual(signature(reloaded.occurrences(of: weekly.id)), signature(weeklyBefore))
        let final = PlanStore(fileURL: fileURL)
        XCTAssertEqual(final.series.map(\.id), [weekly.id])
        XCTAssertEqual(signature(final.occurrences(of: weekly.id)), signature(weeklyBefore))
    }
}
