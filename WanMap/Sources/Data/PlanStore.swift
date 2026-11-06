import Foundation
import Observation

/// plans.json の保存形式（schemaVersion 2）。
/// 予定と繰り返しシリーズの親を1ファイルにまとめることで、
/// 片方だけ保存が成功する不整合を避ける（atomic write は1回で済む）。
struct PlansFile: Codable {
    static let currentVersion = 2
    var schemaVersion: Int
    var plans: [Plan]
    var series: [RecurrenceSeries]
}

/// 明示リセット（resetAllData）の結果。失敗を成功として見せないため、
/// 書けたかどうかと、消せた退避ファイル・失敗内容を呼び出し側へ返す。
struct PlanStoreResetResult {
    /// 予定ファイルを空の新形式で書き直せたか
    var fileReset: Bool
    /// 削除できた旧形式退避ファイルの名前
    var removedBackupFileNames: [String]
    /// 失敗した処理の説明（成功分は含まない）
    var failures: [String]
}

/// 予定データの保持と端末内保存
///
/// 仕様（決定済み）：
/// - 予定は端末内のJSONファイル（Documents/plans.json）に保存する。サーバー同期はまだ無い。
/// - 「今ここ」（isPresence）は作成から2時間で一覧から除外する（Plan.isExpiredPresence）。
/// - 犬の名前は一度入力したら次回使い回せるよう、最後に使った名前を保持する。
/// - 保存形式は schemaVersion 2 のコンテナ。旧・配列形式は読み込み時に移行する
///   （原本は退避してから新形式で保存し直す）。未知の版・破損データは
///   読み込み失敗として保持し、保存で空に潰さない。
///
/// フェーズQレビュー反映（R1〜R3・R8）：
/// - 読込は「ファイルが存在しない＝新規利用」と「それ以外の読込失敗」を区別する。
///   後者は loadFailed として保持し、原本を新規データで上書きしない。
/// - 旧形式の移行は、原本の退避が成功（内容の一致まで確認）できた時だけ進める。
/// - 変更系 API は「保存に成功してからメモリへ反映」し、成否を返す。
///   loadFailed の間は、明示リセット以外の変更をすべて止める。
@Observable
final class PlanStore {
    /// 保存済みの全予定（期限切れの「今ここ」を含む生データ）
    private(set) var plans: [Plan] = []
    /// 繰り返し予定のシリーズ（親）定義
    private(set) var series: [RecurrenceSeries] = []
    /// 最後に使った犬の名前（フォームの初期値に使う）
    private(set) var lastDogName: String = ""
    /// 保存ファイルを読めなかった（未知の形式・破損・読込I/O失敗・移行失敗）かどうか。
    /// true の間は通常の保存が一切書かないため、既存データを空で上書きしない。
    /// ユーザーが設定から明示的にリセットした時だけ解除される。
    private(set) var loadFailed = false

    private let persists: Bool
    private let fileURL: URL
    /// 非永続ストア（プレビュー／UIテスト用シード）での「今ここ」IDの保持先。
    /// 永続ストアでは UserDefaults を使うため、こちらは使わない。
    private var inMemoryOwnPresenceId: UUID?
    private var expiryTimer: Timer?

    private static let lastDogNameKey = "wanmap.lastDogName"

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plans.json")
    }

    init() {
        persists = true
        fileURL = Self.defaultFileURL
        lastDogName = UserDefaults.standard.string(forKey: Self.lastDogNameKey) ?? ""
        load()
        pruneExpiredPresence()
        startExpiryTimer()
    }

    /// テスト用：保存先ファイルを指定する（移行・破損時の挙動を実ファイルで検証するため）
    init(fileURL: URL) {
        persists = true
        self.fileURL = fileURL
        lastDogName = UserDefaults.standard.string(forKey: Self.lastDogNameKey) ?? ""
        load()
        pruneExpiredPresence()
        startExpiryTimer()
    }

    /// プレビュー／デバッグ専用。端末ファイルには読み書きしない。
    init(samplePlans: [Plan]) {
        persists = false
        fileURL = Self.defaultFileURL
        plans = samplePlans.sorted { $0.date < $1.date }
        lastDogName = samplePlans.compactMap { $0.dogName }.last ?? ""
    }

    deinit {
        expiryTimer?.invalidate()
    }

    /// 画面を開いたまま2時間を迎えた「今ここ」も消えるよう、定期的に掃除する
    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneExpiredPresence()
        }
    }

    // MARK: - 読み取り

    /// 期限切れの「今ここ」を除いた、表示対象の予定（日付順）
    var activePlans: [Plan] {
        plans.filter { !$0.isExpiredPresence }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// 指定日の予定（時間帯の順に並べる）
    func plans(on day: Date, calendar: Calendar = WanMapCalendar.shared) -> [Plan] {
        let order: [TimeBand] = [.allDay, .morning, .noon, .night]
        return activePlans
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { order.firstIndex(of: $0.timeBand)! < order.firstIndex(of: $1.timeBand)! }
    }

    /// イベント（募集）だけを開催日が近い順に。過去分は自動で隠す。
    func upcomingEvents(now: Date = Date(), calendar: Calendar = WanMapCalendar.shared) -> [Plan] {
        let today = calendar.startOfDay(for: now)
        return activePlans.filter { $0.isEvent && $0.date >= today }
    }

    // MARK: - CRUD
    // 変更系 API はすべて「候補を作る → 保存する → 成功したらメモリへ反映」の順で動き、
    // 成否を返す。保存に失敗したらメモリも元のままなので、画面が「保存できた見た目」に
    // ならない（フェーズQレビュー R3）。

    @discardableResult
    func add(_ plan: Plan) -> Bool {
        var newPlans = plans
        newPlans.append(plan)
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        rememberDogName(from: plan)
        return true
    }

    @discardableResult
    func update(_ plan: Plan) -> Bool {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return false }
        var newPlans = plans
        newPlans[index] = plan
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        rememberDogName(from: plan)
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        var newPlans = plans
        newPlans.removeAll { $0.id == id }
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        return true
    }

    @discardableResult
    func remove(_ plan: Plan) -> Bool {
        remove(id: plan.id)
    }

    /// 設定画面の「データをリセット」用：予定をすべて消し、付随する端末内状態も初期化する。
    /// ユーザーの明示操作なので、読み込み失敗の保持もここで解除して書き直す。
    /// 旧形式の退避ファイルも削除対象に含め、失敗は結果として返す（R8）。
    /// 順序は保全側に倒す：空ファイルの書き直しに失敗したら、メモリも退避も一切触らない。
    @discardableResult
    func resetAllData() -> PlanStoreResetResult {
        var failures: [String] = []
        var wrote = !persists
        if persists {
            let container = PlansFile(schemaVersion: PlansFile.currentVersion, plans: [], series: [])
            if let data = try? Self.makeEncoder().encode(container) {
                do {
                    try data.write(to: fileURL, options: .atomic)
                    wrote = true
                } catch {
                    failures.append("予定データを初期化できませんでした（\(error.localizedDescription)）")
                }
            } else {
                failures.append("予定データを初期化できませんでした")
            }
        }
        guard wrote else {
            return PlanStoreResetResult(fileReset: false, removedBackupFileNames: [], failures: failures)
        }

        plans = []
        series = []
        loadFailed = false
        lastDogName = ""
        UserDefaults.standard.removeObject(forKey: Self.lastDogNameKey)
        ownPresenceId = nil

        var removedNames: [String] = []
        if persists {
            for url in legacyBackupFileURLs() {
                do {
                    try FileManager.default.removeItem(at: url)
                    removedNames.append(url.lastPathComponent)
                } catch {
                    failures.append("退避ファイル「\(url.lastPathComponent)」を削除できませんでした（\(error.localizedDescription)）")
                }
            }
        }
        return PlanStoreResetResult(fileReset: true, removedBackupFileNames: removedNames,
                                    failures: failures)
    }

    // MARK: - 繰り返し予定（シリーズ）

    /// 予定が属するシリーズ（親）。通常予定・孤立した子は nil。
    func seriesFor(_ plan: Plan) -> RecurrenceSeries? {
        guard let seriesID = plan.seriesID else { return nil }
        return series.first { $0.id == seriesID }
    }

    /// シリーズの残っている回（日付順）
    func occurrences(of seriesID: UUID) -> [Plan] {
        plans.filter { $0.seriesID == seriesID }.sorted { $0.date < $1.date }
    }

    /// シリーズを作成し、全回を実体化して一度だけ保存する。
    /// templatePlan は共通内容の雛形で、その date が初回日になる。
    /// 「今ここ」には繰り返しを設定できない。規則・回数が不正なら何も作らず nil。
    /// 保存に失敗した場合も nil（作れたように見せない）。
    /// イベント締切は各回で個別に設定するものなので、作成時には付けない。
    @discardableResult
    func addSeries(rule: RecurrenceRule, occurrenceCount: Int,
                   templatePlan: Plan,
                   calendar: Calendar = WanMapCalendar.shared) -> RecurrenceSeries? {
        guard !templatePlan.isPresence else { return nil }
        let startDay = calendar.startOfDay(for: templatePlan.date)
        guard let dates = RecurrenceGenerator.dates(rule: rule, start: startDay,
                                                    count: occurrenceCount, calendar: calendar)
        else { return nil }

        let newSeries = RecurrenceSeries(
            id: UUID(), rule: rule, startDate: startDay, occurrenceCount: occurrenceCount,
            timeZoneID: calendar.timeZone.identifier,
            template: PlanTemplate(plan: templatePlan), createdAt: Date()
        )
        let now = Date()
        let children: [Plan] = dates.enumerated().map { index, day in
            var child = templatePlan
            child.id = UUID()
            child.date = day
            child.isPresence = false
            child.eventDeadline = nil
            child.createdAt = now
            child.seriesID = newSeries.id
            child.occurrenceIndex = index
            child.originalDate = day
            child.isSeriesException = false
            return child
        }
        var newPlans = plans
        newPlans.append(contentsOf: children)
        var newSeriesList = series
        newSeriesList.append(newSeries)
        guard persist(plans: newPlans, series: newSeriesList) else { return nil }
        plans = newPlans
        series = newSeriesList
        rememberDogName(templatePlan.dogName)
        return newSeries
    }

    /// 「この回だけ」の変更。所属情報（seriesID／occurrenceIndex／originalDate）は
    /// 保存済みの値を維持し、個別編集フラグを立てる。シリーズに属さない予定なら通常の更新。
    @discardableResult
    func updateOccurrence(_ plan: Plan) -> Bool {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return false }
        let stored = plans[index]
        guard stored.seriesID != nil else {
            return update(plan)
        }
        var updated = plan
        updated.seriesID = stored.seriesID
        updated.occurrenceIndex = stored.occurrenceIndex
        updated.originalDate = stored.originalDate
        updated.isPresence = false
        updated.isSeriesException = true
        var newPlans = plans
        newPlans[index] = updated
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        rememberDogName(from: updated)
        return true
    }

    /// 「この回だけ」削除。削除した回は補充せず、最後の回ならシリーズ親も消す。
    @discardableResult
    func removeOccurrence(_ plan: Plan) -> Bool {
        guard let stored = plans.first(where: { $0.id == plan.id }) else { return false }
        var newPlans = plans
        newPlans.removeAll { $0.id == plan.id }
        var newSeriesList = series
        if let seriesID = stored.seriesID,
           !newPlans.contains(where: { $0.seriesID == seriesID }) {
            newSeriesList.removeAll { $0.id == seriesID }
        }
        guard persist(plans: newPlans, series: newSeriesList) else { return false }
        plans = newPlans
        series = newSeriesList
        return true
    }

    /// シリーズ全体の共通内容変更。前後の雛形を比べて、変わった項目だけを
    /// 残っている全回（過去分を含む）へ反映する。日付は全体変更の対象外で、
    /// 個別に変更した項目も、同じ項目を全体変更すれば上書きされる。
    /// 場所（名前＋緯度＋経度）は1つの論理項目として扱う（R4）：
    /// どれか1つでも変われば、保存済みの場所と混ざらないよう3点をまとめて差し替える。
    @discardableResult
    func updateSeriesContent(seriesID: UUID, newTemplate: PlanTemplate) -> Bool {
        guard let seriesIndex = series.firstIndex(where: { $0.id == seriesID }) else { return false }
        let old = series[seriesIndex].template
        guard old != newTemplate else { return true }
        let placeChanged = newTemplate.placeName != old.placeName
            || newTemplate.latitude != old.latitude
            || newTemplate.longitude != old.longitude

        var newSeriesList = series
        newSeriesList[seriesIndex].template = newTemplate
        var newPlans = plans
        for index in newPlans.indices where newPlans[index].seriesID == seriesID {
            if newTemplate.personName != old.personName { newPlans[index].personName = newTemplate.personName }
            if newTemplate.dogName != old.dogName { newPlans[index].dogName = newTemplate.dogName }
            if placeChanged {
                newPlans[index].placeName = newTemplate.placeName
                newPlans[index].latitude = newTemplate.latitude
                newPlans[index].longitude = newTemplate.longitude
            }
            if newTemplate.timeBand != old.timeBand { newPlans[index].timeBand = newTemplate.timeBand }
            if newTemplate.level != old.level { newPlans[index].level = newTemplate.level }
            if newTemplate.isEvent != old.isEvent { newPlans[index].isEvent = newTemplate.isEvent }
            if newTemplate.hidesOwnLocation != old.hidesOwnLocation {
                newPlans[index].hidesOwnLocation = newTemplate.hidesOwnLocation
            }
        }
        guard persist(plans: newPlans, series: newSeriesList) else { return false }
        plans = newPlans
        series = newSeriesList
        rememberDogName(newTemplate.dogName)
        return true
    }

    /// シリーズ全体を削除する（所属する全回と親を消す。単発予定・別シリーズには触れない）
    @discardableResult
    func removeSeries(id: UUID) -> Bool {
        var newPlans = plans
        newPlans.removeAll { $0.seriesID == id }
        var newSeriesList = series
        newSeriesList.removeAll { $0.id == id }
        guard persist(plans: newPlans, series: newSeriesList) else { return false }
        plans = newPlans
        series = newSeriesList
        return true
    }

    /// シリーズに属する予定から、そのシリーズ全体を削除する
    @discardableResult
    func removeSeries(of plan: Plan) -> Bool {
        guard let seriesID = plan.seriesID else { return false }
        return removeSeries(id: seriesID)
    }

    // MARK: - 自分の「今ここ」

    private static let ownPresenceIdKey = "wanmap.ownPresenceId"

    /// 自分の「今ここ」の plan IDの置き場。永続ストアは UserDefaults（従来どおり）、
    /// 非永続ストアは端末の保存先を汚さないようメモリ上にだけ保持する。
    /// 非永続ストアでも置く／消す／置き換えが成立するので、シード表示での
    /// 「今ここ」操作をUIテストで検証できる（永続ストアの挙動は変わらない）。
    private var ownPresenceId: UUID? {
        get {
            if persists {
                return UserDefaults.standard.string(forKey: Self.ownPresenceIdKey)
                    .flatMap { UUID(uuidString: $0) }
            }
            return inMemoryOwnPresenceId
        }
        set {
            if persists {
                if let newValue {
                    UserDefaults.standard.set(newValue.uuidString, forKey: Self.ownPresenceIdKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.ownPresenceIdKey)
                }
            } else {
                inMemoryOwnPresenceId = newValue
            }
        }
    }

    /// 自分が置いた「今ここ」（期限切れは除く）。端末内にだけ保持し、外部には送らない。
    /// 仮想ユーザー等の他人の presence と取り違えないよう、自分の plan のIDを別に保持する。
    var ownPresence: Plan? {
        guard let id = ownPresenceId,
              let plan = plans.first(where: { $0.id == id && $0.isPresence }),
              !plan.isExpiredPresence
        else { return nil }
        return plan
    }

    /// 「今ここ」を置く。既に置いてある場合は新しい位置に置き換える（前の場所は残さない）。
    /// 場所名は付けない（未登録地点＝人アイコンのみ。自宅が出るのは本人が置いた時だけ）。
    @discardableResult
    func placeOwnPresence(latitude: Double, longitude: Double) -> Bool {
        if ownPresence != nil {
            return moveOwnPresence(latitude: latitude, longitude: longitude)
        }
        var newPlans = plans
        if let oldID = ownPresenceId {
            newPlans.removeAll { $0.id == oldID }
        }
        let plan = Plan(id: UUID(), personName: "自分",
                        dogName: lastDogName.isEmpty ? nil : lastDogName,
                        placeName: "", latitude: latitude, longitude: longitude,
                        date: WanMapCalendar.shared.startOfDay(for: Date()),
                        timeBand: .allDay, level: .going,
                        isEvent: false, eventDeadline: nil,
                        isPresence: true, createdAt: Date())
        newPlans.append(plan)
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        ownPresenceId = plan.id
        return true
    }

    /// 「今ここ」の置き直し（手動操作専用）。
    /// 位置情報の自動追従では呼ばない（R7：配置は本人の明示操作のみが仕様）。
    /// 2時間の起点は置いた時刻のまま。
    @discardableResult
    func moveOwnPresence(latitude: Double, longitude: Double) -> Bool {
        guard let existing = ownPresence,
              existing.latitude != latitude || existing.longitude != longitude,
              let index = plans.firstIndex(where: { $0.id == existing.id })
        else { return false }
        var newPlans = plans
        newPlans[index].latitude = latitude
        newPlans[index].longitude = longitude
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        return true
    }

    /// 「今ここ」を消す
    @discardableResult
    func clearOwnPresence() -> Bool {
        guard let id = ownPresenceId else { return true }
        var newPlans = plans
        newPlans.removeAll { $0.id == id }
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        ownPresenceId = nil
        return true
    }

    // MARK: - 内部処理

    /// 期限切れの「今ここ」を保存データからも取り除く
    @discardableResult
    func pruneExpiredPresence() -> Bool {
        guard plans.contains(where: { $0.isExpiredPresence }) else { return true }
        let newPlans = plans.filter { !$0.isExpiredPresence }
        guard persist(plans: newPlans, series: series) else { return false }
        plans = newPlans
        return true
    }

    private func rememberDogName(from plan: Plan) {
        rememberDogName(plan.dogName)
    }

    private func rememberDogName(_ dogName: String?) {
        guard let name = dogName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        lastDogName = name
        if persists {
            UserDefaults.standard.set(name, forKey: Self.lastDogNameKey)
        }
    }

    private func load() {
        // R1：読込の失敗を分類する。ファイルが存在しない場合だけが新規利用で、
        // それ以外の読込失敗（権限・I/O エラー等）は「データを読めなかった」状態として
        // 保持し、原本を新規データで上書きしない。
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            loadFailed = true
            return
        }
        // まずトップレベルの形で旧形式（配列）と新形式（オブジェクト）を見分ける。
        // 「新形式の decode に失敗したから旧形式で試す」という無条件の
        // フォールバックはしない（破損データと形式の違いを混同しないため）。
        guard let topLevel = try? JSONSerialization.jsonObject(with: data) else {
            loadFailed = true
            return
        }
        let decoder = Self.makeDecoder()
        if topLevel is [Any] {
            // 旧形式（[Plan] の配列）：読めても、原本の退避が成功するまでは移行しない（R2）
            guard let decoded = try? decoder.decode([Plan].self, from: data) else {
                loadFailed = true
                return
            }
            do {
                try backUpLegacyFile(originalData: data)
            } catch {
                // 退避できなければ移行も保存もしない（原本はそのまま残る）
                loadFailed = true
                return
            }
            plans = decoded
            series = []
            if !save() {
                // 新形式への保存に失敗した。原本は旧形式のまま残っているので、
                // 表示は続けつつ変更は止める（次回起動で移行を再試行できる）。
                loadFailed = true
            }
        } else if topLevel is [String: Any] {
            guard let container = try? decoder.decode(PlansFile.self, from: data),
                  container.schemaVersion == PlansFile.currentVersion
            else {
                // 未知の schemaVersion・破損：空データとして保存し直さない
                loadFailed = true
                return
            }
            plans = container.plans
            series = container.series
        } else {
            loadFailed = true
        }
    }

    /// 旧形式退避ファイルのURL（index 1 が基本名 `plans.legacy-v1.json`、
    /// 衝突時は `plans.legacy-v1-2.json` のように連番を足す）
    private func legacyBackupURL(index: Int) -> URL {
        let suffix = index <= 1 ? "legacy-v1.json" : "legacy-v1-\(index).json"
        return fileURL.deletingPathExtension().appendingPathExtension(suffix)
    }

    /// 旧形式の原本を退避する（移行後に問題があっても、元のデータに戻れるように）。
    /// 失敗は呼び出し側へ伝える（throws）。衝突時の方針：
    /// - 既存の退避と内容が同一なら、その退避を再利用して成功扱いにする。
    /// - 内容が異なる（または読めない）退避がある場合は上書きせず、連番の一意名で保全する。
    /// 書き込み後は内容の一致まで確認し、確認できなければ失敗として扱う。
    private func backUpLegacyFile(originalData: Data) throws {
        let fileManager = FileManager.default
        var index = 1
        while true {
            let url = legacyBackupURL(index: index)
            if fileManager.fileExists(atPath: url.path) {
                if let existing = try? Data(contentsOf: url), existing == originalData {
                    return
                }
                index += 1
                continue
            }
            try originalData.write(to: url, options: .atomic)
            guard let written = try? Data(contentsOf: url), written == originalData else {
                throw CocoaError(.fileWriteUnknown)
            }
            return
        }
    }

    /// 端末内に残っている旧形式退避ファイル（基本名＋連番）の一覧。リセット時の削除対象。
    private func legacyBackupFileURLs() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let prefix = "\(baseName).legacy-v1"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0 == "\(prefix).json" || ($0.hasPrefix("\(prefix)-") && $0.hasSuffix(".json")) }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// 現在のメモリ内容を指定の内容として保存する。成功した時だけ true。
    /// 非永続ストアでは書く先が無いので常に true（メモリ反映のみで成立する）。
    /// loadFailed の間は、明示リセット以外からは書かない。
    @discardableResult
    private func persist(plans newPlans: [Plan], series newSeries: [RecurrenceSeries]) -> Bool {
        guard persists else { return true }
        guard !loadFailed else { return false }
        let container = PlansFile(schemaVersion: PlansFile.currentVersion,
                                  plans: newPlans, series: newSeries)
        guard let data = try? Self.makeEncoder().encode(container) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 現在のメモリ内容をそのまま保存する（移行直後など、メモリが正の場面用）
    @discardableResult
    private func save() -> Bool {
        persist(plans: plans, series: series)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
