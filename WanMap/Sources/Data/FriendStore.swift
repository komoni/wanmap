import Foundation
import Observation

/// 友達データの保持と端末内保存（モック）
///
/// 仕様（決定済み）：
/// - IDは2層で区別する：表示・検索用ID（アプリ発行ID `wan-xxxxxx`）と
///   不変の内部ID `usr-…`（AppUser 参照）。Instagram連携は行わない（2026-11-13決定）。
/// - 自分の AppUser は端末内に1件だけ保持する。
/// - 友達関係と申請状態は端末内のJSONファイル（Documents/friends.json）に保存する。
///   実通信はまだ無い：検索・申請・承認はすべて端末内のモック動作で、
///   申請は送ると自動承認される。仮想ユーザー「ムギ」からの受信申請が1件、
///   初期モックとして届いている。
/// - 「見せない」（hideFromMe）は「この人には自分の位置・存在を見せない」リスト。
///   実データはこの relations の1か所だけで、友達画面と設定画面は同じデータを触る。
/// - 共有範囲の原則：位置・予定が見えるのは「アプリ内友達 ∩ アプリ利用者 ∩
///   共有同意 ∩ 見せないリスト外」だけ。全員に見える設計にはしない。
@Observable
final class FriendStore {
    /// 自分（端末内に1件）
    private(set) var me: AppUser
    /// 友達関係の一覧（申請中・受信中・友達）
    private(set) var relations: [FriendRelation] = []

    private let persists: Bool

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("friends.json")
    }

    init() {
        persists = true
        me = Self.makeSelf()
        relations = Self.seedRelations
        if !load() { save() }
    }

    /// プレビュー専用。端末ファイルには読み書きしない。
    private init(me: AppUser, relations: [FriendRelation]) {
        persists = false
        self.me = me
        self.relations = relations
    }

    static var preview: FriendStore {
        FriendStore(
            me: AppUser(internalId: "usr-preview",
                        appIssuedId: "wan-prev00", displayName: "自分", dogName: nil),
            relations: [
                FriendRelation(user: mockDirectory[0], state: .incoming, hideFromMe: false),
                FriendRelation(user: mockDirectory[1], state: .friends, hideFromMe: false),
                FriendRelation(user: mockDirectory[3], state: .friends, hideFromMe: true),
            ])
    }

    // MARK: - 仮想ユーザー（モックの相手）

    /// ID検索とコード追加でヒットする仮想ユーザー。
    /// SeedData の予定と名前を揃えてある（飼い主名／犬の名前）。
    static let mockDirectory: [AppUser] = [
        AppUser(internalId: "usr-mock-mugi", appIssuedId: "wan-mugi27", displayName: "ケン", dogName: "ムギ",
                breedId: "siberian-husky", dogColorId: "black-white"),
        AppUser(internalId: "usr-mock-sora",
                appIssuedId: "wan-sora31", displayName: "タクミ", dogName: "ソラ",
                breedId: "toy-poodle", dogColorId: "red"),
        AppUser(internalId: "usr-mock-haru",
                appIssuedId: "wan-haru08", displayName: "ミサキ", dogName: "ハル",
                breedId: "siberian-husky", dogColorId: "silver-white"),
        AppUser(internalId: "usr-mock-momo",
                appIssuedId: "wan-momo52", displayName: "ユイ", dogName: "モモ",
                breedId: "chihuahua", dogColorId: "fawn"),
        AppUser(internalId: "usr-mock-kotaro",
                appIssuedId: "wan-kota66", displayName: "シン", dogName: "コタロウ",
                breedId: "mixed", dogColorId: "brown-white"),
        AppUser(internalId: "usr-mock-reo",
                appIssuedId: "wan-reo19", displayName: "あかり", dogName: "レオ",
                breedId: "chihuahua", dogColorId: "black-tan"),
    ]

    /// 初期モック：ムギからの受信申請が1件届いている
    private static var seedRelations: [FriendRelation] {
        [FriendRelation(user: mockDirectory[0], state: .incoming, hideFromMe: false)]
    }

    private static func makeSelf() -> AppUser {
        AppUser(internalId: "usr-" + randomToken(6),
                appIssuedId: "wan-" + randomToken(6),
                displayName: "自分",
                dogName: nil)
    }

    private static func randomToken(_ length: Int) -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - 読み取り

    var friends: [FriendRelation] { relations.filter { $0.state == .friends } }
    var incomingRequests: [FriendRelation] { relations.filter { $0.state == .incoming } }

    func relation(for user: AppUser) -> FriendRelation? {
        relations.first { $0.user.internalId == user.internalId }
    }

    /// ID・名前・犬の名前で仮想ユーザーを検索する（既に関係がある相手は除く）。
    /// 正規化は施設検索と同じルール（全角→半角・小文字化・記号除去）。
    func searchDirectory(_ query: String) -> [AppUser] {
        let q = FacilityStore.normalize(query)
        guard !q.isEmpty else { return [] }
        return Self.mockDirectory.filter { user in
            if let rel = relation(for: user), rel.state != .none { return false }
            let haystacks = [user.publicId, user.appIssuedId, user.internalId,
                             user.displayName, user.dogName ?? ""]
            return haystacks.contains { FacilityStore.normalize($0).contains(q) }
        }
    }

    // MARK: - 申請・承認（モック）

    /// 申請を送る。モックでは端末内で即時に自動承認され、そのまま友達になる。
    func sendRequest(to user: AppUser) {
        upsert(user: user, state: .friends)
        save()
    }

    /// 受信申請を承認する
    func approve(internalId: String) {
        guard let index = relations.firstIndex(where: { $0.user.internalId == internalId }) else { return }
        relations[index].state = .friends
        save()
    }

    /// 受信申請を断る（関係自体を消す）
    func reject(internalId: String) {
        relations.removeAll { $0.user.internalId == internalId }
        save()
    }

    enum AddByCodeResult {
        case added(AppUser)
        case alreadyFriends(AppUser)
        case notFound
    }

    /// QRコード／手入力のIDで友達追加する。表示ID（@付き含む）・アプリ発行ID・内部IDの
    /// いずれでも照合する。見つかればモックとして相互同意済みの扱いで友達になる。
    func add(byCode code: String) -> AddByCodeResult {
        let q = FacilityStore.normalize(code)
        guard !q.isEmpty,
              let user = Self.mockDirectory.first(where: {
                  FacilityStore.normalize($0.publicId) == q
                      || FacilityStore.normalize($0.appIssuedId) == q
                      || FacilityStore.normalize($0.internalId) == q
              })
        else { return .notFound }
        if let rel = relation(for: user), rel.state == .friends {
            return .alreadyFriends(user)
        }
        upsert(user: user, state: .friends)
        save()
        return .added(user)
    }

    // MARK: - 自分の犬（設定タブ「自分の犬」。すべて任意項目で、未設定でも困らない）

    /// 自分の犬の名前。空文字は未設定（nil）として持つ
    func updateMyDogName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        me.dogName = trimmed.isEmpty ? nil : trimmed
        save()
    }

    /// 自分の犬の犬種。犬種を変えたら毛色は未設定に戻す
    /// （色名が同じでも犬種ごとに意味が違うため、機械的に引き継がない）
    func updateMyDogBreed(breedId: String?) {
        if me.breedId != breedId { me.dogColorId = nil }
        me.breedId = breedId
        save()
    }

    /// 自分の犬の毛色
    func updateMyDogColor(colorId: String?) {
        me.dogColorId = colorId
        save()
    }

    // MARK: - 見せないリスト

    /// 「この人には自分の位置・存在を見せない」の切り替え。
    /// 友達画面と設定画面はこの同じデータを触るので、片方の変更がもう片方にも反映される。
    func setHide(internalId: String, _ hide: Bool) {
        guard let index = relations.firstIndex(where: { $0.user.internalId == internalId }) else { return }
        relations[index].hideFromMe = hide
        save()
    }

    // MARK: - リセット

    /// 自分のIDを作り直し、友達関係を初期モック（ムギからの申請1件）に戻す
    func resetAll() {
        me = Self.makeSelf()
        relations = Self.seedRelations
        save()
    }

    // MARK: - 内部処理

    private func upsert(user: AppUser, state: FriendRequestState) {
        if let index = relations.firstIndex(where: { $0.user.internalId == user.internalId }) {
            relations[index].state = state
        } else {
            relations.append(FriendRelation(user: user, state: state, hideFromMe: false))
        }
    }

    private struct PersistedState: Codable {
        var me: AppUser
        var relations: [FriendRelation]
    }

    /// 保存済みがあれば読み込む。読み込めたら true。
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return false }
        me = decoded.me
        relations = decoded.relations
        return true
    }

    private func save() {
        guard persists else { return }
        let state = PersistedState(me: me, relations: relations)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
