import Foundation
import CoreLocation

/// ユーザーが追加した場所の種別
enum UserPlaceKind: String, Codable, CaseIterable {
    case dogRun = "ドッグラン"
    case dogCafe = "ドッグカフェ"
    case other = "その他"

    /// 地図マーカーの絵文字（公式施設と同じ流儀。その他はピン印）
    var markerEmoji: String {
        switch self {
        case .dogRun: return "🐶"
        case .dogCafe: return "☕"
        case .other: return "📍"
        }
    }
}

/// 追加した場所の公開範囲
/// デフォルトは「招待した人だけ」。共有の対象になるのは場所名であり、
/// 生の座標そのものを公開する設計にはしない（決定済み）。
enum PlaceVisibility: String, Codable, CaseIterable {
    case inviteOnly = "招待した人だけ"
    case friends = "友達"
    case everyone = "全員"
}

/// ユーザーが自分で追加した場所（自宅の庭のドッグランなど、公式施設に無い地点）
///
/// 設計（決定済み）：
/// - 公式施設データ（facilities.json）には混ぜない。表示・検索の層でのみマージする。
/// - ユーザーが追加・編集した情報は初期施設情報より優先度が高く、検索・候補では先に出す。
struct UserPlace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: UserPlaceKind
    var address: String?
    var latitude: Double
    var longitude: Double
    var visibility: PlaceVisibility = .inviteOnly
    var memo: String?
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
