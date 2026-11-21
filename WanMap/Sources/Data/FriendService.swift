import FirebaseFirestore
import Foundation
import Observation

/// サーバーの友達機能（フェーズ2単位2-4）。
/// - サインイン中だけ動く。FriendStore へサーバー状態を写し、
///   画面側は従来どおり FriendStore だけを見る（橋渡し役）
/// - 申請ドキュメントのIDは fromUid_toUid の決め打ち
///   （ルールが承認済み申請の存在を引く前提。firestore.rules 参照）
/// - 承認は2段階（申請を approved に確定 → 友達関係を作成）。
///   バッチでは申請の更新がルールから見えないため同時に行わない。
///   2段階目が失敗しても、承認済みで友達関係が無い申請を見つけたら
///   次のスナップショットで自動で作り直す（自己修復）
/// - ブロックはルール側の土台のみで、画面はまだ無い（最小形）
@MainActor
@Observable
final class FriendService {

    /// 連携中か（サインイン＋プロフィール確定で true）
    private(set) var isActive = false
    /// 友達画面へ出す失敗メッセージ
    var errorMessage: String?

    @ObservationIgnored private var myUid: String?
    @ObservationIgnored private var myDisplayId = ""
    @ObservationIgnored private var myDisplayName = ""
    @ObservationIgnored private weak var store: FriendStore?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []

    // スナップショットの合成材料
    @ObservationIgnored private var incomingRelations: [FriendRelation] = []
    @ObservationIgnored private var outgoingRelations: [FriendRelation] = []
    @ObservationIgnored private var friendRelations: [FriendRelation] = []
    @ObservationIgnored private var hiddenTargets: Set<String> = []
    @ObservationIgnored private var friendUids: Set<String> = []
    /// 友達uidの集合（同期サービスが購読先を決めるのに使う）
    var currentFriendUids: Set<String> { friendUids }
    /// 友達の集合が変わった時の通知先（SyncService が差す）
    @ObservationIgnored var onFriendUidsChanged: ((Set<String>) -> Void)?
    @ObservationIgnored private var profileCache: [String: AppUser] = [:]
    @ObservationIgnored private var fetchingProfiles: Set<String> = []

    // MARK: - ID の組み立て（ルール側の約束と一致させる。単体テスト対象）

    nonisolated static func pairId(_ a: String, _ b: String) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    nonisolated static func requestId(from: String, to: String) -> String {
        "\(from)_\(to)"
    }

    /// 検索入力の正規化：前後の空白・先頭の @ を落として小文字化する
    nonisolated static func normalizeCode(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("@") { s.removeFirst() }
        return s
    }

    // MARK: - 開始・停止

    func start(uid: String, displayId: String, displayName: String, store: FriendStore) {
        if isActive, myUid == uid { return }
        stopListeners()
        myUid = uid
        myDisplayId = displayId
        myDisplayName = displayName
        self.store = store
        isActive = true
        store.serverHideHandler = { [weak self] targetId, hide in
            Task { await self?.setHidden(targetUid: targetId, hidden: hide) }
        }

        let db = Firestore.firestore()

        // 届いている申請（受け手＝自分）
        listeners.append(
            db.collection("friendRequests").whereField("toUid", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    Task { @MainActor in self.handleIncoming(snapshot.documents) }
                })

        // 送った申請（送り手＝自分）
        listeners.append(
            db.collection("friendRequests").whereField("fromUid", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    Task { @MainActor in self.handleOutgoing(snapshot.documents) }
                })

        // 友達関係（members に自分を含む）
        listeners.append(
            db.collection("friendships").whereField("members", arrayContains: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    Task { @MainActor in self.handleFriendships(snapshot.documents) }
                })

        // 見せない相手（自分の targets）
        listeners.append(
            db.collection("hiddenFrom").document(uid).collection("targets")
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    Task { @MainActor in
                        self.hiddenTargets = Set(snapshot.documents.map(\.documentID))
                        self.publish()
                    }
                })
    }

    func stop() {
        stopListeners()
        isActive = false
        myUid = nil
        incomingRelations = []
        outgoingRelations = []
        friendRelations = []
        hiddenTargets = []
        friendUids = []
        store?.serverHideHandler = nil
        store?.exitServerMode()
        store = nil
    }

    private func stopListeners() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    // MARK: - スナップショットの処理

    private func handleIncoming(_ docs: [QueryDocumentSnapshot]) {
        var relations: [FriendRelation] = []
        for doc in docs {
            let data = doc.data()
            guard let fromUid = data["fromUid"] as? String,
                  let status = data["status"] as? String else { continue }
            if status == "approved" {
                healFriendship(with: fromUid)
            } else if status == "pending" {
                let fromId = data["fromDisplayId"] as? String ?? ""
                let fromName = data["fromDisplayName"] as? String ?? ""
                let user = AppUser(internalId: fromUid,
                                   appIssuedId: fromId,
                                   displayName: fromName.isEmpty ? fromId : fromName,
                                   dogName: nil)
                relations.append(FriendRelation(user: user, state: .incoming, hideFromMe: false))
            }
        }
        incomingRelations = relations
        publish()
    }

    private func handleOutgoing(_ docs: [QueryDocumentSnapshot]) {
        var relations: [FriendRelation] = []
        for doc in docs {
            let data = doc.data()
            guard let toUid = data["toUid"] as? String,
                  let status = data["status"] as? String else { continue }
            if status == "approved" {
                healFriendship(with: toUid)
            } else if status == "pending" {
                // 送り先の表示名は友達になるまで引けない（ルールの閲覧ゲート）。
                // 行には表示IDだけを出す
                let user = AppUser(internalId: toUid,
                                   appIssuedId: pendingDisplayIds[toUid] ?? "",
                                   displayName: pendingDisplayIds[toUid] ?? "",
                                   dogName: nil)
                relations.append(FriendRelation(user: user, state: .outgoing, hideFromMe: false))
            }
        }
        outgoingRelations = relations
        publish()
    }

    /// 送った申請の表示IDメモ（申請時に覚えて、申請中リストの表示に使う。
    /// 再起動後も残るよう UserDefaults に持つ）
    @ObservationIgnored private var pendingDisplayIds: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "friendService.pendingDisplayIds") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "friendService.pendingDisplayIds") }
    }

    private func handleFriendships(_ docs: [QueryDocumentSnapshot]) {
        guard let myUid else { return }
        var others: [String] = []
        for doc in docs {
            guard let members = doc.data()["members"] as? [String] else { continue }
            others.append(contentsOf: members.filter { $0 != myUid })
        }
        let newUids = Set(others)
        let changed = newUids != friendUids
        friendUids = newUids
        if changed { onFriendUidsChanged?(newUids) }
        for other in others where profileCache[other] == nil {
            fetchProfile(uid: other)
        }
        rebuildFriends()
        publish()
    }

    private func fetchProfile(uid: String) {
        guard !fetchingProfiles.contains(uid) else { return }
        fetchingProfiles.insert(uid)
        Task { @MainActor in
            defer { fetchingProfiles.remove(uid) }
            let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = doc?.data() else { return }
            let displayId = data["displayId"] as? String ?? ""
            let name = data["displayName"] as? String ?? ""
            profileCache[uid] = AppUser(internalId: uid,
                                        appIssuedId: displayId,
                                        displayName: name.isEmpty ? displayId : name,
                                        dogName: nil)
            rebuildFriends()
            publish()
        }
    }

    private func rebuildFriends() {
        friendRelations = friendUids.compactMap { uid in
            profileCache[uid].map {
                FriendRelation(user: $0, state: .friends, hideFromMe: hiddenTargets.contains(uid))
            }
        }
    }

    /// 承認済みなのに友達関係が無い申請を見つけたら作り直す
    private func healFriendship(with otherUid: String) {
        guard let myUid, !friendUids.contains(otherUid) else { return }
        let pair = Self.pairId(myUid, otherUid)
        Task { @MainActor in
            try? await Firestore.firestore().collection("friendships").document(pair)
                .setData(["members": [myUid, otherUid].sorted(),
                          "createdAt": FieldValue.serverTimestamp()])
        }
    }

    private func publish() {
        rebuildFriends()
        store?.applyServerRelations(incomingRelations + outgoingRelations + friendRelations)
    }

    // MARK: - 検索・申請

    enum LookupResult: Equatable {
        case found(uid: String)
        case notFound
        case isSelf
    }

    /// 表示IDから相手の uid を引く（displayIds の単体取得。ルールで許可済み）
    func lookup(displayId rawCode: String) async -> LookupResult {
        let code = Self.normalizeCode(rawCode)
        guard let myUid else { return .notFound }
        if code == myDisplayId { return .isSelf }
        do {
            let doc = try await Firestore.firestore().collection("displayIds").document(code).getDocument()
            guard let uid = doc.data()?["uid"] as? String else { return .notFound }
            if uid == myUid { return .isSelf }
            return .found(uid: uid)
        } catch {
            return .notFound
        }
    }

    /// 申請を送る。拒否済みの申請があれば再申請として pending に戻す
    func sendRequest(toUid: String, displayId: String) async {
        guard let myUid else { return }
        var ids = pendingDisplayIds
        ids[toUid] = displayId
        pendingDisplayIds = ids
        let db = Firestore.firestore()
        let ref = db.collection("friendRequests").document(Self.requestId(from: myUid, to: toUid))
        let expires = Timestamp(date: Date().addingTimeInterval(30 * 24 * 60 * 60))
        do {
            let existing = try await ref.getDocument()
            if let status = existing.data()?["status"] as? String {
                switch status {
                case "pending":
                    errorMessage = "すでに申請中です"
                    return
                case "approved":
                    errorMessage = "すでに友達です"
                    return
                case "rejected":
                    try await ref.updateData([
                        "status": "pending",
                        "createdAt": FieldValue.serverTimestamp(),
                        "expiresAt": expires,
                    ])
                    errorMessage = nil
                    return
                default:
                    break
                }
            }
            try await ref.setData([
                "fromUid": myUid,
                "toUid": toUid,
                "fromDisplayId": myDisplayId,
                "fromDisplayName": myDisplayName,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": expires,
            ])
            errorMessage = nil
        } catch {
            errorMessage = "申請を送れませんでした。通信状態を確認してもう一度お試しください"
        }
    }

    /// 受信申請を承認する（2段階：承認の確定 → 友達関係の作成）
    func approve(fromUid: String) async {
        guard let myUid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("friendRequests")
                .document(Self.requestId(from: fromUid, to: myUid))
                .updateData(["status": "approved"])
            try await db.collection("friendships")
                .document(Self.pairId(myUid, fromUid))
                .setData(["members": [myUid, fromUid].sorted(),
                          "createdAt": FieldValue.serverTimestamp()])
            errorMessage = nil
        } catch {
            // 2段階目だけ失敗した場合は、承認済み申請の自己修復が次回に作り直す
            errorMessage = "承認の処理を完了できませんでした。時間をおいてもう一度お試しください"
        }
    }

    /// 受信申請を断る
    func reject(fromUid: String) async {
        guard let myUid else { return }
        do {
            try await Firestore.firestore().collection("friendRequests")
                .document(Self.requestId(from: fromUid, to: myUid))
                .updateData(["status": "rejected"])
            errorMessage = nil
        } catch {
            errorMessage = "処理できませんでした。通信状態を確認してもう一度お試しください"
        }
    }

    /// 送った申請を取り消す
    func cancelOutgoing(toUid: String) async {
        guard let myUid else { return }
        do {
            try await Firestore.firestore().collection("friendRequests")
                .document(Self.requestId(from: myUid, to: toUid))
                .delete()
            errorMessage = nil
        } catch {
            errorMessage = "取り消せませんでした。通信状態を確認してもう一度お試しください"
        }
    }

    /// 見せない設定（FriendStore.setHide から転送される）
    func setHidden(targetUid: String, hidden: Bool) async {
        guard let myUid else { return }
        let ref = Firestore.firestore().collection("hiddenFrom").document(myUid)
            .collection("targets").document(targetUid)
        do {
            if hidden {
                try await ref.setData(["createdAt": FieldValue.serverTimestamp()])
            } else {
                try await ref.delete()
            }
        } catch {
            errorMessage = "見せない設定を保存できませんでした"
        }
    }
}
