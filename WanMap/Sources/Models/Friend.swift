import Foundation

/// アプリ内ユーザー
/// 表示・検索用IDは Instagram のユーザーネーム（連携時）。
/// 内部IDは不変の数値IDで、ユーザーネーム変更でも友達関係は切れない（決定済み設計）。
struct AppUser: Codable, Identifiable, Equatable {
    var id: String { internalId }
    let internalId: String          // 不変の内部ID（例: usr-xxxx）
    var instagramUsername: String?  // 連携時の表示・検索用ID
    var appIssuedId: String         // 未連携時の表示・検索用ID（例: wan-xxxxxx）
    var displayName: String
    var dogName: String?
    /// 自分の犬の犬種（Breed マスタのID）。未設定は nil（地図では汎用ミックスで表示）
    var breedId: String? = nil
    /// 毛色（その犬種の colors のID）。犬種と組で意味を持つ
    var dogColorId: String? = nil

    var publicId: String { instagramUsername.map { "@\($0)" } ?? appIssuedId }
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
