import Foundation

/// アプリ内ユーザー
/// 表示・検索用IDはアプリ発行ID（wan-xxxxxx）。Instagram連携は行わない
/// （公式APIでは友達判定ができないため、2026-11-13に不採用を決定）。
/// 友達追加は、このIDやQRコードを相手に送り、相手が承認する形。
/// 内部IDは不変で、表示名が変わっても友達関係は切れない。
struct AppUser: Codable, Identifiable, Equatable {
    var id: String { internalId }
    let internalId: String          // 不変の内部ID（例: usr-xxxx）
    var appIssuedId: String         // 表示・検索用ID（例: wan-xxxxxx）
    var displayName: String
    var dogName: String?
    /// 自分の犬の犬種（Breed マスタのID）。未設定は nil（地図では汎用ミックスで表示）
    var breedId: String? = nil
    /// 毛色（その犬種の colors のID）。犬種と組で意味を持つ
    var dogColorId: String? = nil

    var publicId: String { appIssuedId }
}

enum FriendRequestState: String, Codable {
    case none, outgoing, incoming, friends
}

/// 友達関係（サーバー側が正。ここは端末側の表現）
struct FriendRelation: Codable, Identifiable, Equatable {
    var id: String { user.internalId }
    var user: AppUser
    var state: FriendRequestState
    /// 「この人には自分の位置・存在を見せない」リストに入っているか
    var hideFromMe: Bool
}
