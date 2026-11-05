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

/// 予定データの保持と端末内保存
///
/// 仕様（決定済み）：
/// - 予定は端末内のJSONファイル（Documents/plans.json）に保存する。サーバー同期はまだ無い。
/// - 「今ここ」（isPresence）は作成から2時間で一覧から除外する（Plan.isExpiredPresence）。
/// - 犬の名前は一度入力したら次回使い回せるよう、最後に使った名前を保持する。
/// - 保存形式は schemaVersion 2 のコンテナ。旧・配列形式は読み込み時に移行する
///   （原本は退避してから新形式で保存し直す）。未知の版・破損データは
///   読み込み失敗として保持し、保存で空に潰さない。
@Observable
final class PlanStore {
    /// 保存済みの全予定（期限切れの「今ここ」を含む生データ）
    private(set) var plans: [Plan] = []
    /// 繰り返し予定のシリーズ（親）定義
    private(set) var series: [RecurrenceSeries] = []
    /// 最後に使った犬の名前（フォームの初期値に使う）
    private(set) var lastDogName: String = ""
    /// 保存ファイルを読めなかった（未知の形式・破損）かどうか。
    /// true の間は save() が一切書かないため、既存データを空で上書きしない。
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
    func plans(on day: Date, calendar: Calendar = .current) -> [Plan] {
        let order: [TimeBand] = [.allDay, .morning, .noon, .night]
        return activePlans
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { order.firstIndex(of: $0.timeBand)! < order.firstIndex(of: $1.timeBand)! }
    }

    /// イベント（募集）だけを開催日が近い順に。過去分は自動で隠す。
    func upcomingEvents(now: Date = Date(), calendar: Calendar = .current) -> [Plan] {
        let today = calendar.startOfDay(for: now)
        return activePlans.filter { $0.isEvent && $0.date >= today }
    }

    // MARK: - CRUD

    func add(_ plan: Plan) {
        plans.append(plan)
        rememberDogName(from: plan)
        save()
    }

    func update(_ plan: Plan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        rememberDogName(from: plan)
        save()
    }

    func remove(id: UUID) {
        plans.removeAll { $0.id == id }
        save()
    }

    func remove(_ plan: Plan) {
        remove(id: plan.id)
    }

    /// 設定画面の「データをリセット」用：予定をすべて消し、付随する端末内状態も初期化する
    /// ユーザーの明示操作なので、読み込み失敗の保持もここで解除して書き直す。
    func resetAllData() {
        plans = []
        series = []
        loadFailed = false
        lastDogName = ""
        UserDefaults.standard.removeObject(forKey: Self.lastDogNameKey)
        ownPresenceId = nil
        save()
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
    /// イベント締切は各回で個別に設定するものなので、作成時には付けない。
    @discardableResult
    func addSeries(rule: RecurrenceRule, occurrenceCount: Int,
                   templatePlan: Plan, calendar: Calendar = .current) -> RecurrenceSeries? {
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
        plans.append(contentsOf: children)
        series.append(newSeries)
        rememberDogName(templatePlan.dogName)
        save()
        return newSeries
    }

    /// 「この回だけ」の変更。所属情報（seriesID／occurrenceIndex／originalDate）は
    /// 保存済みの値を維持し、個別編集フラグを立てる。シリーズに属さない予定なら通常の更新。
    func updateOccurrence(_ plan: Plan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        let stored = plans[index]
        guard stored.seriesID != nil else {
            update(plan)
            return
        }
        var updated = plan
        updated.seriesID = stored.seriesID
        updated.occurrenceIndex = stored.occurrenceIndex
        updated.originalDate = stored.originalDate
        updated.isPresence = false
        updated.isSeriesException = true
        plans[index] = updated
        rememberDogName(from: updated)
        save()
    }

    /// 「この回だけ」削除。削除した回は補充せず、最後の回ならシリーズ親も消す。
    func removeOccurrence(_ plan: Plan) {
        guard let stored = plans.first(where: { $0.id == plan.id }) else { return }
        plans.removeAll { $0.id == plan.id }
        if let seriesID = stored.seriesID,
           !plans.contains(where: { $0.seriesID == seriesID }) {
            series.removeAll { $0.id == seriesID }
        }
        save()
    }

    /// シリーズ全体の共通内容変更。前後の雛形を比べて、変わった項目だけを
    /// 残っている全回（過去分を含む）へ反映する。日付は全体変更の対象外で、
    /// 個別に変更した項目も、同じ項目を全体変更すれば上書きされる。
    func updateSeriesContent(seriesID: UUID, newTemplate: PlanTemplate) {
        guard let seriesIndex = series.firstIndex(where: { $0.id == seriesID }) else { return }
        let old = series[seriesIndex].template
        guard old != newTemplate else { return }
        series[seriesIndex].template = newTemplate

        for index in plans.indices where plans[index].seriesID == seriesID {
            if newTemplate.personName != old.personName { plans[index].personName = newTemplate.personName }
            if newTemplate.dogName != old.dogName { plans[index].dogName = newTemplate.dogName }
            if newTemplate.placeName != old.placeName { plans[index].placeName = newTemplate.placeName }
            if newTemplate.latitude != old.latitude { plans[index].latitude = newTemplate.latitude }
            if newTemplate.longitude != old.longitude { plans[index].longitude = newTemplate.longitude }
            if newTemplate.timeBand != old.timeBand { plans[index].timeBand = newTemplate.timeBand }
            if newTemplate.level != old.level { plans[index].level = newTemplate.level }
            if newTemplate.isEvent != old.isEvent { plans[index].isEvent = newTemplate.isEvent }
            if newTemplate.hidesOwnLocation != old.hidesOwnLocation {
                plans[index].hidesOwnLocation = newTemplate.hidesOwnLocation
            }
        }
        rememberDogName(newTemplate.dogName)
        save()
    }

    /// シリーズ全体を削除する（所属する全回と親を消す。単発予定・別シリーズには触れない）
    func removeSeries(id: UUID) {
        plans.removeAll { $0.seriesID == id }
        series.removeAll { $0.id == id }
        save()
    }

    /// シリーズに属する予定から、そのシリーズ全体を削除する
    func removeSeries(of plan: Plan) {
        guard let seriesID = plan.seriesID else { return }
        removeSeries(id: seriesID)
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
    func placeOwnPresence(latitude: Double, longitude: Double) {
        if ownPresence != nil {
            moveOwnPresence(latitude: latitude, longitude: longitude)
            return
        }
        clearOwnPresence()
        let plan = Plan(id: UUID(), personName: "自分",
                        dogName: lastDogName.isEmpty ? nil : lastDogName,
                        placeName: "", latitude: latitude, longitude: longitude,
                        date: Calendar.current.startOfDay(for: Date()),
                        timeBand: .allDay, level: .going,
                        isEvent: false, eventDeadline: nil,
                        isPresence: true, createdAt: Date())
        plans.append(plan)
        ownPresenceId = plan.id
        save()
    }

    /// 移動したら「今ここ」を新しい位置に置き換える（2時間の起点は置いた時刻のまま）
    func moveOwnPresence(latitude: Double, longitude: Double) {
        guard let existing = ownPresence,
              existing.latitude != latitude || existing.longitude != longitude,
              let index = plans.firstIndex(where: { $0.id == existing.id })
        else { return }
        plans[index].latitude = latitude
        plans[index].longitude = longitude
        save()
    }

    /// 「今ここ」を消す
    func clearOwnPresence() {
        if let id = ownPresenceId {
            plans.removeAll { $0.id == id }
        }
        ownPresenceId = nil
        save()
    }

    // MARK: - 内部処理

    /// 期限切れの「今ここ」を保存データからも取り除く
    func pruneExpiredPresence() {
        let before = plans.count
        plans.removeAll { $0.isExpiredPresence }
        if plans.count != before { save() }
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
        // ファイルが無いのは新規利用なので、失敗ではない
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // まずトップレベルの形で旧形式（配列）と新形式（オブジェクト）を見分ける。
        // 「新形式の decode に失敗したから旧形式で試す」という無条件の
        // フォールバックはしない（破損データと形式の違いを混同しないため）。
        guard let topLevel = try? JSONSerialization.jsonObject(with: data) else {
            loadFailed = true
            return
        }
        let decoder = Self.makeDecoder()
        if topLevel is [Any] {
            // 旧形式（[Plan] の配列）：読めたら原本を退避し、新形式で保存し直す
            guard let decoded = try? decoder.decode([Plan].self, from: data) else {
                loadFailed = true
                return
            }
            plans = decoded
            series = []
            backUpLegacyFile(originalData: data)
            save()
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

    /// 旧形式の原本を退避する（移行後に問題があっても、元のデータに戻れるように）
    private func backUpLegacyFile(originalData: Data) {
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("legacy-v1.json")
        try? originalData.write(to: backupURL, options: .atomic)
    }

    private func save() {
        guard persists else { return }
        // 読み込みに失敗したデータは、通常の保存では絶対に潰さない
        guard !loadFailed else { return }
        let container = PlansFile(schemaVersion: PlansFile.currentVersion,
                                  plans: plans, series: series)
        guard let data = try? Self.makeEncoder().encode(container) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
