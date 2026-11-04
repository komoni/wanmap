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
