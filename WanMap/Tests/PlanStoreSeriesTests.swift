import XCTest
@testable import WanMap

/// PlanStore の繰り返し（シリーズ）操作の検証。
/// 保存しないサンプル経路で意味論（実体化・この回だけ・全体・削除）を確かめ、
/// 永続化は専用の一時ファイルで確かめる（通常データには触れない）。
final class PlanStoreSeriesTests: XCTestCase {

    private var tokyo: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }

    /// 2026/11/1（日曜）開始の毎週シリーズ用の規則と雛形
    private func weeklyFixture() -> (rule: RecurrenceRule, template: Plan) {
        let start = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let rule = RecurrenceRule(kind: .weekly, startDate: start, calendar: tokyo)
        var template = makePlan(placeName: "ドッグウィズ", date: start)
        template.dogName = "ポチ"
        return (rule, template)
    }

    private func dateLabel(_ date: Date) -> String {
        let c = tokyo.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)/\(c.month!)/\(c.day!)"
    }

    // MARK: - 作成（実体化）

    func testAddSeries_全回が実体化され親と紐づく() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])

        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)

        XCTAssertNotNil(series)
        guard let series else { return }
        let children = store.occurrences(of: series.id)
        XCTAssertEqual(children.map { dateLabel($0.date) },
                       ["2026/11/1", "2026/11/8", "2026/11/15"])
        XCTAssertEqual(children.map(\.occurrenceIndex), [0, 1, 2])
        XCTAssertTrue(children.allSatisfy { $0.seriesID == series.id })
        XCTAssertTrue(children.allSatisfy { $0.originalDate == $0.date })
        XCTAssertTrue(children.allSatisfy { !$0.isSeriesException && !$0.isPresence })
        XCTAssertEqual(Set(children.map(\.id)).count, 3, "各回のIDは別々のはず")
        XCTAssertEqual(store.series.count, 1)
        XCTAssertEqual(store.seriesFor(children[0])?.id, series.id)
        XCTAssertEqual(series.template.placeName, "ドッグウィズ")
        XCTAssertEqual(series.occurrenceCount, 3)
    }

    func testAddSeries_今ここには繰り返しを設定できない() {
        let (rule, template) = weeklyFixture()
        var presence = template
        presence.isPresence = true
        let store = PlanStore(samplePlans: [])

        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: presence, calendar: tokyo)

        XCTAssertNil(series)
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertTrue(store.series.isEmpty)
    }

    func testAddSeries_不正な回数では何も作られない() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])

        XCTAssertNil(store.addSeries(rule: rule, occurrenceCount: 4,
                                     templatePlan: template, calendar: tokyo))
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertTrue(store.series.isEmpty)
    }

    // MARK: - この回だけの変更・削除

    func testUpdateOccurrence_所属情報を維持し例外フラグが立つ() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!
        let children = store.occurrences(of: series.id)

        var edited = children[1]
        let originalID = edited.id
        edited.date = tokyo.date(byAdding: .day, value: 1, to: edited.date)!
        edited.placeName = "SKドッグラン"
        edited.seriesID = nil  // 呼び出し側が所属を落としても、保存済みの所属が維持されること
        store.updateOccurrence(edited)

        let after = store.occurrences(of: series.id)
        XCTAssertEqual(after.count, 3)
        let changed = after.first { $0.id == originalID }
        XCTAssertEqual(changed?.placeName, "SKドッグラン")
        XCTAssertEqual(changed.map { dateLabel($0.date) }, "2026/11/9")
        XCTAssertEqual(changed?.seriesID, series.id)
        XCTAssertEqual(changed?.occurrenceIndex, 1)
        XCTAssertEqual(changed.map { dateLabel($0.originalDate!) }, "2026/11/8",
                       "当初の開催日は個別変更後も維持されるはず")
        XCTAssertEqual(changed?.isSeriesException, true)
        // 他の回には触れていない
        XCTAssertEqual(after.filter { $0.id != originalID }.map(\.isSeriesException),
                       [false, false])
    }

    func testRemoveOccurrence_削除した回は補充されず親は残る() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!
        let middle = store.occurrences(of: series.id)[1]

        store.removeOccurrence(middle)

        let remaining = store.occurrences(of: series.id)
        XCTAssertEqual(remaining.map(\.occurrenceIndex), [0, 2], "再採番も補充もされないはず")
        XCTAssertEqual(store.series.count, 1, "回が残っている間は親も残る")
    }

    func testRemoveOccurrence_最後の回を消すと親も消える() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!

        for child in store.occurrences(of: series.id) {
            store.removeOccurrence(child)
        }

        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertTrue(store.series.isEmpty, "子の無いシリーズ親が残ってはいけない")
    }

    // MARK: - シリーズ全体の変更・削除

    func testUpdateSeriesContent_変更した項目だけ全回へ反映される() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!

        // 2回目だけ犬名を個別変更しておく
        var second = store.occurrences(of: series.id)[1]
        second.dogName = "ハナ"
        store.updateOccurrence(second)
        let datesBefore = store.occurrences(of: series.id).map { dateLabel($0.date) }

        // 全体変更：場所だけを変える
        var newTemplate = series.template
        newTemplate.placeName = "SKドッグラン"
        newTemplate.latitude = 34.7921028
        newTemplate.longitude = 137.0232936
        store.updateSeriesContent(seriesID: series.id, newTemplate: newTemplate)

        var children = store.occurrences(of: series.id)
        XCTAssertTrue(children.allSatisfy { $0.placeName == "SKドッグラン" })
        XCTAssertTrue(children.allSatisfy { $0.latitude == 34.7921028 })
        XCTAssertEqual(children.map(\.dogName), ["ポチ", "ハナ", "ポチ"],
                       "変えていない項目（犬名）は個別変更も含めて維持されるはず")
        XCTAssertEqual(children.map { dateLabel($0.date) }, datesBefore,
                       "日付は全体変更の対象外")

        // 全体変更：犬名を変えると、個別変更した回の同じ項目も上書きされる
        var renamed = store.seriesFor(children[0])!.template
        renamed.dogName = "ジロ"
        renamed.personName = "ジロ"
        store.updateSeriesContent(seriesID: series.id, newTemplate: renamed)
        children = store.occurrences(of: series.id)
        XCTAssertEqual(children.map(\.dogName), ["ジロ", "ジロ", "ジロ"])
        XCTAssertEqual(store.seriesFor(children[0])?.template.dogName, "ジロ")
    }

    func testRemoveSeries_全回と親が消え単発予定と別シリーズは残る() {
        let (rule, template) = weeklyFixture()
        let store = PlanStore(samplePlans: [])
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!
        let other = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!
        let single = makePlan(placeName: "単発の場所")
        store.add(single)

        store.removeSeries(id: series.id)

        XCTAssertTrue(store.occurrences(of: series.id).isEmpty)
        XCTAssertNil(store.seriesFor(single))
        XCTAssertEqual(store.occurrences(of: other.id).count, 3)
        XCTAssertTrue(store.plans.contains { $0.id == single.id })
        XCTAssertEqual(store.series.map(\.id), [other.id])
    }

    // MARK: - 永続化（専用の一時ファイル）

    func testPersistence_シリーズが保存され削除した回は再読み込みでも戻らない() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wanmap-series-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("plans.json")
        let (rule, template) = weeklyFixture()

        let store = PlanStore(fileURL: fileURL)
        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: template, calendar: tokyo)!
        let childIDs = store.occurrences(of: series.id).map(\.id)

        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.series.map(\.id), [series.id])
        XCTAssertEqual(reloaded.occurrences(of: series.id).map(\.id), childIDs,
                       "再読み込みで親子関係と各回のIDが一致するはず")

        reloaded.removeOccurrence(reloaded.occurrences(of: series.id)[0])
        let reloadedAgain = PlanStore(fileURL: fileURL)
        XCTAssertEqual(reloadedAgain.occurrences(of: series.id).count, 2,
                       "削除した回が再読み込みで復活してはいけない")
        XCTAssertEqual(reloadedAgain.series.count, 1)
    }
}

/// plans.json の形式移行・破損耐性の検証（専用の一時ファイルのみを使う）
final class PlanFileMigrationTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wanmap-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("plans.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 旧形式（配列）。繰り返し関連の項目も hidesOwnLocation も無い、移行前の実データ相当。
    private let legacyJSON = """
    [
      {
        "id": "11111111-2222-3333-4444-555555555555",
        "personName": "タクミ",
        "dogName": "ソラ",
        "placeName": "ドッグウィズ",
        "latitude": 35.1649375,
        "longitude": 137.08455,
        "date": "2026-11-01T00:00:00Z",
        "timeBand": "朝",
        "level": "行く",
        "isEvent": false,
        "isPresence": false,
        "createdAt": "2026-10-30T12:00:00Z"
      }
    ]
    """

    func testMigration_旧形式が読み込まれ既存フィールドが保持される() throws {
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)

        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.plans.count, 1)
        let plan = store.plans[0]
        XCTAssertEqual(plan.id.uuidString, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(plan.personName, "タクミ")
        XCTAssertEqual(plan.dogName, "ソラ")
        XCTAssertEqual(plan.placeName, "ドッグウィズ")
        XCTAssertEqual(plan.latitude, 35.1649375)
        XCTAssertEqual(plan.longitude, 137.08455)
        XCTAssertEqual(plan.timeBand, .morning)
        XCTAssertEqual(plan.level, .going)
        XCTAssertEqual(plan.createdAt, ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z"))
        XCTAssertEqual(plan.date, ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        // 後から足した項目は既定値で補われる
        XCTAssertFalse(plan.hidesOwnLocation)
        XCTAssertNil(plan.seriesID)
        XCTAssertNil(plan.occurrenceIndex)
        XCTAssertNil(plan.originalDate)
        XCTAssertFalse(plan.isSeriesException)
        XCTAssertTrue(store.series.isEmpty)

        // 新形式（コンテナ）で保存し直されている
        let rewritten = try Data(contentsOf: fileURL)
        let topLevel = try JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        XCTAssertEqual(topLevel?["schemaVersion"] as? Int, PlansFile.currentVersion)

        // 旧形式の原本が退避されている
        let backupURL = directory.appendingPathComponent("plans.legacy-v1.json")
        let backup = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertEqual(backup, legacyJSON)

        // 移行後の再読み込みでも同じ予定が読める
        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.plans.map(\.id), store.plans.map(\.id))
        XCTAssertFalse(reloaded.loadFailed)
    }

    func testCorrupt_破損データは読み込み失敗になり通常の保存では潰れない() throws {
        try "{broken json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed)
        XCTAssertTrue(store.plans.isEmpty)

        store.add(makePlan())
        let after = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(after, "{broken json", "読めなかったデータを空で上書きしてはいけない")

        // ユーザーの明示的なリセットだけは、失敗保持を解除して書き直せる
        store.resetAllData()
        XCTAssertFalse(store.loadFailed)
        let reset = try Data(contentsOf: fileURL)
        let topLevel = try JSONSerialization.jsonObject(with: reset) as? [String: Any]
        XCTAssertEqual(topLevel?["schemaVersion"] as? Int, PlansFile.currentVersion)
    }

    func testUnknownVersion_未知のschemaVersionは読み込み失敗になり潰れない() throws {
        let futureJSON = #"{"schemaVersion": 99, "plans": [], "series": []}"#
        try futureJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed)

        store.add(makePlan())
        let after = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(after, futureJSON)
    }

    func testCorruptContainer_新形式でも中身が壊れていれば読み込み失敗になる() throws {
        // schemaVersion は合っているが予定の必須項目が欠けている＝破損として扱う
        let brokenJSON = #"{"schemaVersion": 2, "plans": [{"id": "x"}], "series": []}"#
        try brokenJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed)
        XCTAssertTrue(store.plans.isEmpty)
    }
}
