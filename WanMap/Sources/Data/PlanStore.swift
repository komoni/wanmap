import Foundation
import Observation

/// 予定データの保持と端末内保存
///
/// 仕様（決定済み）：
/// - 予定は端末内のJSONファイル（Documents/plans.json）に保存する。サーバー同期はまだ無い。
/// - 「今ここ」（isPresence）は作成から2時間で一覧から除外する（Plan.isExpiredPresence）。
/// - 犬の名前は一度入力したら次回使い回せるよう、最後に使った名前を保持する。
@Observable
final class PlanStore {
    /// 保存済みの全予定（期限切れの「今ここ」を含む生データ）
    private(set) var plans: [Plan] = []
    /// 最後に使った犬の名前（フォームの初期値に使う）
    private(set) var lastDogName: String = ""

    private let persists: Bool
    /// 非永続ストア（プレビュー／UIテスト用シード）での「今ここ」IDの保持先。
    /// 永続ストアでは UserDefaults を使うため、こちらは使わない。
    private var inMemoryOwnPresenceId: UUID?
    private var expiryTimer: Timer?

    private static let lastDogNameKey = "wanmap.lastDogName"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plans.json")
    }

    init() {
        persists = true
        lastDogName = UserDefaults.standard.string(forKey: Self.lastDogNameKey) ?? ""
        load()
        pruneExpiredPresence()
        // 画面を開いたまま2時間を迎えた「今ここ」も消えるよう、定期的に掃除する
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneExpiredPresence()
        }
    }

    /// プレビュー／デバッグ専用。端末ファイルには読み書きしない。
    init(samplePlans: [Plan]) {
        persists = false
        plans = samplePlans.sorted { $0.date < $1.date }
        lastDogName = samplePlans.compactMap { $0.dogName }.last ?? ""
    }

    deinit {
        expiryTimer?.invalidate()
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
    func resetAllData() {
        plans = []
        lastDogName = ""
        UserDefaults.standard.removeObject(forKey: Self.lastDogNameKey)
        ownPresenceId = nil
        save()
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
        guard let name = plan.dogName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        lastDogName = name
        if persists {
            UserDefaults.standard.set(name, forKey: Self.lastDogNameKey)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.makeDecoder().decode([Plan].self, from: data)
        else { return }
        plans = decoded
    }

    private func save() {
        guard persists else { return }
        guard let data = try? Self.makeEncoder().encode(plans) else { return }
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
