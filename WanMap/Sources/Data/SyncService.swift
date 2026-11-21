import Foundation
import Observation
import FirebaseFirestore

/// フェーズ2単位2-5：予定と「今ここ」のサーバー同期。
/// - 自分の予定は PlanStore の変更を検知して Firestore の plans/{planId} へ写す（差分方式）。
///   位置を見せない設定（hidesOwnLocation）の予定はサーバーへ上げない
/// - 自分の「今ここ」は presence/{uid} にも写す（期限は placedAt + 2時間。ルールで担保）
/// - 友達の予定は所有者ごとに購読し、PlanStore の表示専用レイヤー（friendPlans）へ渡す。
///   友達の「今ここ」は presence/{uid} から組み立てる
/// サインイン中だけ動く。サインアウトで全購読を止め、友達分は表示から消す
@MainActor
@Observable
final class SyncService {
    private(set) var isActive = false

    @ObservationIgnored private var myUid: String?
    @ObservationIgnored private weak var planStore: PlanStore?
    /// 最後にサーバーへ写せた自分の予定（差分の基準）
    @ObservationIgnored private var lastSynced: [UUID: Plan] = [:]
    @ObservationIgnored private var lastPresenceSignature: String?
    @ObservationIgnored private var friendListeners: [String: [ListenerRegistration]] = [:]
    @ObservationIgnored private var friendPlansByUid: [String: [Plan]] = [:]
    @ObservationIgnored private var friendPresenceByUid: [String: Plan] = [:]
    @ObservationIgnored private var presenceIds: [String: UUID] = [:]
    @ObservationIgnored private var tracking = false

    private var db: Firestore { Firestore.firestore() }

    func start(uid: String, planStore: PlanStore, friendService: FriendService) {
        stop()
        myUid = uid
        self.planStore = planStore
        isActive = true
        friendService.onFriendUidsChanged = { [weak self] uids in
            self?.reconcileFriendListeners(uids)
        }
        reconcileFriendListeners(friendService.currentFriendUids)
        trackOwnPlans()
        Task { await syncOwnPlans() }
    }

    func stop() {
        isActive = false
        tracking = false
        myUid = nil
        for regs in friendListeners.values { regs.forEach { $0.remove() } }
        friendListeners = [:]
        friendPlansByUid = [:]
        friendPresenceByUid = [:]
        presenceIds = [:]
        lastSynced = [:]
        lastPresenceSignature = nil
        planStore?.applyServerFriendPlans([])
        planStore = nil
    }

    // MARK: - 自分の予定の書き込み

    /// PlanStore.plans の変更を一度だけ受け取る観察を張り直し続ける
    private func trackOwnPlans() {
        guard !tracking, let planStore else { return }
        tracking = true
        withObservationTracking {
            _ = planStore.plans
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.tracking = false
                await self.syncOwnPlans()
                self.trackOwnPlans()
            }
        }
    }

    private func syncOwnPlans() async {
        guard let myUid, let planStore else { return }
        // 位置を見せない予定はサーバーへ上げない（＝サーバー側の「現在」からも外す）
        let current = planStore.plans.filter { !$0.hidesOwnLocation }
        let currentById = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var newSynced = lastSynced
        for (id, _) in lastSynced where currentById[id] == nil {
            do {
                try await db.collection("plans").document(id.uuidString).delete()
                newSynced[id] = nil
            } catch {
                // 失敗したら次回の差分で再試行する（newSynced に残す）
            }
        }
        for plan in current where lastSynced[plan.id] != plan {
            do {
                try await db.collection("plans").document(plan.id.uuidString)
                    .setData(Self.firestoreData(for: plan, ownerUid: myUid))
                newSynced[plan.id] = plan
            } catch {
                // 同上
            }
        }
        lastSynced = newSynced
        await syncOwnPresence(from: planStore.plans)
    }

    private func syncOwnPresence(from plans: [Plan]) async {
        guard let myUid else { return }
        let active = plans.first { $0.isPresence && !$0.isExpiredPresence && !$0.hidesOwnLocation }
        let signature = active.map { "\($0.id.uuidString)|\($0.createdAt.timeIntervalSince1970)" }
        guard signature != lastPresenceSignature else { return }
        let ref = db.collection("presence").document(myUid)
        if let active {
            var data: [String: Any] = [
                "personName": active.personName,
                "placeName": active.placeName,
                "placedAt": Timestamp(date: active.createdAt),
                "expiresAt": Timestamp(date: active.createdAt.addingTimeInterval(2 * 3600)),
            ]
            if let dogName = active.dogName { data["dogName"] = dogName }
            if let lat = active.latitude, let lng = active.longitude {
                data["latitude"] = lat
                data["longitude"] = lng
            }
            do {
                try await ref.setData(data)
                lastPresenceSignature = signature
            } catch {
                // 次回の差分で再試行する
            }
        } else {
            do {
                try await ref.delete()
                lastPresenceSignature = nil
            } catch {
                // 同上
            }
        }
    }

    // MARK: - 友達の予定の購読

    private func reconcileFriendListeners(_ uids: Set<String>) {
        guard isActive else { return }
        for uid in Array(friendListeners.keys) where !uids.contains(uid) {
            friendListeners[uid]?.forEach { $0.remove() }
            friendListeners[uid] = nil
            friendPlansByUid[uid] = nil
            friendPresenceByUid[uid] = nil
            presenceIds[uid] = nil
        }
        for uid in uids where friendListeners[uid] == nil {
            subscribeFriend(uid)
        }
        publishFriendPlans()
    }

    private func subscribeFriend(_ uid: String) {
        var regs: [ListenerRegistration] = []
        let plansQuery = db.collection("plans").whereField("ownerUid", isEqualTo: uid)
        regs.append(plansQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    // 閲覧ゲートで弾かれた等。その友達の予定は空として扱う
                    self.friendPlansByUid[uid] = []
                } else {
                    self.friendPlansByUid[uid] = (snapshot?.documents ?? [])
                        .compactMap { Self.plan(from: $0, ownerUid: uid) }
                        .filter { !$0.isPresence }
                }
                self.publishFriendPlans()
            }
        })
        regs.append(db.collection("presence").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.friendPresenceByUid[uid] = nil
                    if error == nil, let snapshot, snapshot.exists, let data = snapshot.data(),
                       let placedAt = (data["placedAt"] as? Timestamp)?.dateValue(),
                       placedAt.addingTimeInterval(2 * 3600) > Date() {
                        let id = self.presenceIds[uid] ?? UUID()
                        self.presenceIds[uid] = id
                        self.friendPresenceByUid[uid] = Plan(
                            id: id,
                            personName: data["personName"] as? String ?? "",
                            dogName: data["dogName"] as? String,
                            placeName: data["placeName"] as? String ?? "",
                            latitude: data["latitude"] as? Double,
                            longitude: data["longitude"] as? Double,
                            date: placedAt,
                            timeBand: .now,
                            level: .going,
                            isEvent: false,
                            eventDeadline: nil,
                            isPresence: true,
                            createdAt: placedAt,
                            ownerUid: uid)
                    }
                    self.publishFriendPlans()
                }
            })
        friendListeners[uid] = regs
    }

    private func publishFriendPlans() {
        let all = friendPlansByUid.values.flatMap { $0 }
            + friendPresenceByUid.values.compactMap { $0 }
        planStore?.applyServerFriendPlans(Array(all))
    }

    // MARK: - 変換

    private static func firestoreData(for plan: Plan, ownerUid: String) -> [String: Any] {
        var d: [String: Any] = [
            "ownerUid": ownerUid,
            "personName": plan.personName,
            "placeName": plan.placeName,
            "date": Timestamp(date: plan.date),
            "timeBand": plan.timeBand.rawValue,
            "level": plan.level.rawValue,
            "isEvent": plan.isEvent,
            "isPresence": plan.isPresence,
            "createdAt": Timestamp(date: plan.createdAt),
            "hidesOwnLocation": plan.hidesOwnLocation,
            "isSeriesException": plan.isSeriesException,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let v = plan.dogName { d["dogName"] = v }
        if let v = plan.latitude { d["latitude"] = v }
        if let v = plan.longitude { d["longitude"] = v }
        if let v = plan.eventDeadline { d["eventDeadline"] = Timestamp(date: v) }
        if let v = plan.seriesID { d["seriesID"] = v.uuidString }
        if let v = plan.occurrenceIndex { d["occurrenceIndex"] = v }
        if let v = plan.originalDate { d["originalDate"] = Timestamp(date: v) }
        return d
    }

    private static func plan(from doc: QueryDocumentSnapshot, ownerUid: String) -> Plan? {
        let d = doc.data()
        guard let id = UUID(uuidString: doc.documentID),
              let date = (d["date"] as? Timestamp)?.dateValue() else { return nil }
        return Plan(
            id: id,
            personName: d["personName"] as? String ?? "",
            dogName: d["dogName"] as? String,
            placeName: d["placeName"] as? String ?? "",
            latitude: d["latitude"] as? Double,
            longitude: d["longitude"] as? Double,
            date: date,
            timeBand: TimeBand(rawValue: d["timeBand"] as? String ?? "") ?? .allDay,
            level: AttendanceLevel(rawValue: d["level"] as? String ?? "") ?? .going,
            isEvent: d["isEvent"] as? Bool ?? false,
            eventDeadline: (d["eventDeadline"] as? Timestamp)?.dateValue(),
            isPresence: d["isPresence"] as? Bool ?? false,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? date,
            hidesOwnLocation: d["hidesOwnLocation"] as? Bool ?? false,
            seriesID: (d["seriesID"] as? String).flatMap { UUID(uuidString: $0) },
            occurrenceIndex: d["occurrenceIndex"] as? Int,
            originalDate: (d["originalDate"] as? Timestamp)?.dateValue(),
            isSeriesException: d["isSeriesException"] as? Bool ?? false,
            ownerUid: ownerUid)
    }
}
