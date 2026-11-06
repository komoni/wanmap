import XCTest
@testable import WanMap

/// フェーズQレビュー（R1〜R8）の安全性修正の検証。
/// 読込の失敗分類・旧形式退避の保全・保存→反映の順序・場所の一括更新・
/// 暦の統一・手動配置の不変条件を、専用の一時ファイルだけで確かめる
/// （通常データには触れない）。
final class PlanStoreSafetyTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wanmap-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("plans.json")
    }

    override func tearDownWithError() throws {
        // 読み取り専用にしたテストが残っていても消せるように戻してから削除する
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    /// 旧形式（配列）の実データ相当
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

    private func setDirectoryWritable(_ writable: Bool) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: directory.path)
    }

    // MARK: - R1：読込の失敗分類

    func testLoad_ファイルが無い場合は新規として扱われる() throws {
        let store = PlanStore(fileURL: fileURL)
        XCTAssertFalse(store.loadFailed, "ファイルが無いのは新規利用で、失敗ではないはず")
        XCTAssertTrue(store.plans.isEmpty)

        XCTAssertTrue(store.add(makePlan()), "新規なら保存できるはず")
        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.plans.count, 1)
        XCTAssertFalse(reloaded.loadFailed)
    }

    func testLoad_保存先がディレクトリなら読み込み失敗になり上書きしない() throws {
        // 読込I/O失敗の再現：plans.json の場所にディレクトリがある
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed, "存在するのに読めない場合は失敗として保持するはず")
        XCTAssertTrue(store.plans.isEmpty)

        XCTAssertFalse(store.add(makePlan()), "読めなかった間は保存できないはず")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "原本（ディレクトリ）が新規データで潰されてはいけない")
    }

    // MARK: - R2：旧形式退避の保全

    func testMigration_退避先に別の内容があると連番で保全される() throws {
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        let otherBackup = "以前の退避（別内容）"
        let baseBackupURL = directory.appendingPathComponent("plans.legacy-v1.json")
        try otherBackup.write(to: baseBackupURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)

        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.plans.count, 1)
        // 既存の退避は上書きされず、原本は連番ファイルへ保全される
        XCTAssertEqual(try String(contentsOf: baseBackupURL, encoding: .utf8), otherBackup)
        let secondBackupURL = directory.appendingPathComponent("plans.legacy-v1-2.json")
        XCTAssertEqual(try String(contentsOf: secondBackupURL, encoding: .utf8), legacyJSON)
        // 本体は新形式へ移行している
        let rewritten = try Data(contentsOf: fileURL)
        let topLevel = try JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        XCTAssertEqual(topLevel?["schemaVersion"] as? Int, PlansFile.currentVersion)
    }

    func testMigration_退避先に同一内容があれば再利用される() throws {
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        let baseBackupURL = directory.appendingPathComponent("plans.legacy-v1.json")
        try legacyJSON.write(to: baseBackupURL, atomically: true, encoding: .utf8)

        let store = PlanStore(fileURL: fileURL)

        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.plans.count, 1)
        let secondBackupURL = directory.appendingPathComponent("plans.legacy-v1-2.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondBackupURL.path),
                       "同一内容の退避があるなら、連番ファイルは作らないはず")
    }

    func testMigration_退避に失敗したら移行せず次回再試行できる() throws {
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        setDirectoryWritable(false)

        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed, "退避できなければ移行に進んではいけない")
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), legacyJSON,
                       "原本は旧形式のまま残るはず")

        // 書けるようになれば、次の読み込みで移行が完了する
        setDirectoryWritable(true)
        let retried = PlanStore(fileURL: fileURL)
        XCTAssertFalse(retried.loadFailed)
        XCTAssertEqual(retried.plans.count, 1)
        let backupURL = directory.appendingPathComponent("plans.legacy-v1.json")
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), legacyJSON)
    }

    // MARK: - R3：保存→反映の順序と成否の返却

    func testSave_保存できない時は変更がメモリにも反映されず成否が返る() throws {
        // 保存先の親フォルダが無い＝書き込みが必ず失敗する状態
        let missingDirURL = directory.appendingPathComponent("not-created-\(UUID().uuidString)")
        let unreachableURL = missingDirURL.appendingPathComponent("plans.json")
        let store = PlanStore(fileURL: unreachableURL)
        XCTAssertFalse(store.loadFailed, "ファイルが無いのは新規扱いのはず")

        XCTAssertFalse(store.add(makePlan()), "保存失敗は false で返るはず")
        XCTAssertTrue(store.plans.isEmpty, "保存できていない変更が画面に出てはいけない")

        let start = WanMapCalendar.shared.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let rule = RecurrenceRule(kind: .weekly, startDate: start, calendar: WanMapCalendar.shared)
        XCTAssertNil(store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: makePlan(date: start)),
                     "保存できないシリーズ作成は nil で返るはず")
        XCTAssertTrue(store.series.isEmpty)

        // 書けるようになれば、同じ操作が成功して永続化される
        try FileManager.default.createDirectory(at: missingDirURL, withIntermediateDirectories: true)
        XCTAssertTrue(store.add(makePlan()))
        XCTAssertEqual(PlanStore(fileURL: unreachableURL).plans.count, 1)
    }

    func testLoadFailed_変更はすべて止まりリセットだけが回復できる() throws {
        try "{broken json".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.loadFailed)

        XCTAssertFalse(store.add(makePlan()))
        XCTAssertFalse(store.update(makePlan()))
        XCTAssertFalse(store.remove(id: UUID()))
        XCTAssertTrue(store.plans.isEmpty)

        let result = store.resetAllData()
        XCTAssertTrue(result.fileReset)
        XCTAssertFalse(store.loadFailed)
        XCTAssertTrue(store.add(makePlan()), "リセット後は通常どおり保存できるはず")
    }

    // MARK: - R8：リセットは退避ファイルも対象にし、結果を報告する

    func testReset_旧形式の退避ファイルも削除され結果に報告される() throws {
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        let store = PlanStore(fileURL: fileURL)  // 移行で plans.legacy-v1.json ができる
        let baseBackupURL = directory.appendingPathComponent("plans.legacy-v1.json")
        let secondBackupURL = directory.appendingPathComponent("plans.legacy-v1-2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseBackupURL.path))
        try "stray".write(to: secondBackupURL, atomically: true, encoding: .utf8)

        let result = store.resetAllData()

        XCTAssertTrue(result.fileReset)
        XCTAssertTrue(result.failures.isEmpty, "失敗していないはず：\(result.failures)")
        XCTAssertTrue(result.removedBackupFileNames.contains("plans.legacy-v1.json"))
        XCTAssertTrue(result.removedBackupFileNames.contains("plans.legacy-v1-2.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseBackupURL.path),
                       "退避ファイルがリセット後も残ってはいけない")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondBackupURL.path))
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertFalse(store.loadFailed)
    }

    // MARK: - シリーズの場所（R4・R5）

    /// 座標付きの毎週シリーズ（親の場所＝ドッグウィズ）を作る
    private func seriesFixture(in store: PlanStore) -> RecurrenceSeries {
        let cal = WanMapCalendar.shared
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let rule = RecurrenceRule(kind: .weekly, startDate: start, calendar: cal)
        var template = makePlan(placeName: "ドッグウィズ", date: start)
        template.latitude = 35.1649375
        template.longitude = 137.08455
        return store.addSeries(rule: rule, occurrenceCount: 3, templatePlan: template, calendar: cal)!
    }

    func testUpdateSeriesContent_場所は名前と座標をまとめて差し替える() {
        let store = PlanStore(samplePlans: [])
        let series = seriesFixture(in: store)

        // 2回目だけ別の場所（名前＋座標）へ個別変更しておく
        var second = store.occurrences(of: series.id)[1]
        second.placeName = "SKドッグラン"
        second.latitude = 34.7921028
        second.longitude = 137.0232936
        store.updateOccurrence(second)

        // シリーズ全体では場所の名前だけを変える（座標は親のものを指定）
        var newTemplate = store.seriesFor(second)!.template
        newTemplate.placeName = "新しい場所"
        XCTAssertTrue(store.updateSeriesContent(seriesID: series.id, newTemplate: newTemplate))

        // 全回が「新しい場所＋親の座標」で揃い、個別変更した回の座標と混ざらない
        for child in store.occurrences(of: series.id) {
            XCTAssertEqual(child.placeName, "新しい場所")
            XCTAssertEqual(child.latitude, 35.1649375,
                           "名前だけ親・座標だけ個別変更、のような混ざり方があってはいけない")
            XCTAssertEqual(child.longitude, 137.08455)
        }
    }

    func testUpdateSeriesContent_場所が変わらなければ個別変更した回の場所に触れない() {
        let store = PlanStore(samplePlans: [])
        let series = seriesFixture(in: store)

        var second = store.occurrences(of: series.id)[1]
        second.placeName = "SKドッグラン"
        second.latitude = 34.7921028
        second.longitude = 137.0232936
        store.updateOccurrence(second)

        // 場所は親のまま、時間帯だけを全体変更する
        var newTemplate = store.seriesFor(second)!.template
        newTemplate.timeBand = .morning
        XCTAssertTrue(store.updateSeriesContent(seriesID: series.id, newTemplate: newTemplate))

        let children = store.occurrences(of: series.id)
        XCTAssertTrue(children.allSatisfy { $0.timeBand == .morning })
        let kept = children.first { $0.id == second.id }
        XCTAssertEqual(kept?.placeName, "SKドッグラン", "親の場所で暗黙に置き換えてはいけない")
        XCTAssertEqual(kept?.latitude, 34.7921028)
        XCTAssertEqual(kept?.longitude, 137.0232936)
    }

    func testUpdateSeriesContent_座標を外す変更も混ざらず一括で反映される() {
        let store = PlanStore(samplePlans: [])
        let series = seriesFixture(in: store)

        var newTemplate = series.template
        newTemplate.latitude = nil
        newTemplate.longitude = nil
        XCTAssertTrue(store.updateSeriesContent(seriesID: series.id, newTemplate: newTemplate))

        for child in store.occurrences(of: series.id) {
            XCTAssertEqual(child.placeName, "ドッグウィズ")
            XCTAssertNil(child.latitude, "片方だけ座標が残る混ざり方があってはいけない")
            XCTAssertNil(child.longitude)
        }
    }

    // MARK: - R6：暦の統一

    func testSharedCalendar_グレゴリオ暦と東京で統一されている() {
        XCTAssertEqual(WanMapCalendar.shared.identifier, .gregorian)
        XCTAssertEqual(WanMapCalendar.shared.timeZone.identifier, "Asia/Tokyo")
    }

    func testAddSeries_既定カレンダーでも毎月同日が月末寄せになる() {
        // 端末の既定カレンダーに依存しないこと：カレンダーを渡さない本番経路でも、
        // 共有のグレゴリオ暦（Asia/Tokyo）で生成される（1/31→2/28→3/31）
        let cal = WanMapCalendar.shared
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let rule = RecurrenceRule(kind: .monthlyDay, startDate: start, calendar: cal)
        let store = PlanStore(samplePlans: [])

        let series = store.addSeries(rule: rule, occurrenceCount: 3,
                                     templatePlan: makePlan(date: start))
        XCTAssertNotNil(series)
        guard let series else { return }
        XCTAssertEqual(series.timeZoneID, "Asia/Tokyo")
        let labels = store.occurrences(of: series.id).map { plan in
            let c = cal.dateComponents([.month, .day], from: plan.date)
            return "\(c.month!)/\(c.day!)"
        }
        XCTAssertEqual(labels, ["1/31", "2/28", "3/31"])
    }

    // MARK: - R7・小修正：「今ここ」の手動配置と2時間境界

    func testPresence_明示操作以外では今ここは動かない() throws {
        let store = PlanStore(fileURL: fileURL)
        XCTAssertTrue(store.placeOwnPresence(latitude: 35.0, longitude: 137.0))

        // 予定の追加・更新・掃除など、他の操作では座標が変わらない
        let plan = makePlan()
        XCTAssertTrue(store.add(plan))
        var edited = plan
        edited.placeName = "別の場所"
        XCTAssertTrue(store.update(edited))
        store.pruneExpiredPresence()
        XCTAssertEqual(store.ownPresence?.latitude, 35.0)
        XCTAssertEqual(store.ownPresence?.longitude, 137.0)

        // 同じ座標への置き直しは無変更として false、別の座標は true で動く
        XCTAssertFalse(store.moveOwnPresence(latitude: 35.0, longitude: 137.0))
        XCTAssertTrue(store.moveOwnPresence(latitude: 35.5, longitude: 137.5))

        // 再読み込みしても、最後に明示操作で置いた位置のまま
        let reloaded = PlanStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.ownPresence?.latitude, 35.5)
        XCTAssertEqual(reloaded.ownPresence?.longitude, 137.5)

        // 自分の「今ここ」IDは UserDefaults に残るため、後始末しておく
        reloaded.resetAllData()
    }

    func testPresence_ちょうど2時間で失効する() {
        let placedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let presence = makePlan(isPresence: true, createdAt: placedAt)
        XCTAssertFalse(presence.isExpiredPresence(at: placedAt.addingTimeInterval(7199)),
                       "2時間未満はまだ有効なはず")
        XCTAssertTrue(presence.isExpiredPresence(at: placedAt.addingTimeInterval(7200)),
                      "ちょうど2時間で失効するはず（境界は >= ）")
        XCTAssertFalse(makePlan(isPresence: false, createdAt: placedAt)
            .isExpiredPresence(at: placedAt.addingTimeInterval(7200)),
            "通常の予定は失効しない")
    }
}
