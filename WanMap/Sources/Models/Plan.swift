import Foundation
import CoreLocation

/// 行く度合い（手入力の予定は「確定情報」なので推測度は付けない。決定済み仕様）
enum AttendanceLevel: String, Codable, CaseIterable {
    case going = "行く"
    case probably = "多分行く"
    case ifSunny = "晴れなら行く"
}

/// 時間帯
enum TimeBand: String, Codable, CaseIterable {
    case allDay = "終日"
    case morning = "朝"
    case noon = "昼"
    case night = "夜"
}

/// 予定（集まりの予告・「今ここ」も含む）
struct Plan: Codable, Identifiable, Equatable {
    var id: UUID
    var personName: String          // 表示名（犬の名前/飼い主名）
    var dogName: String?
    var placeName: String           // 登録済みの場所名（未登録地点は空＝人アイコンのみ）
    var latitude: Double?
    var longitude: Double?
    var date: Date                  // 対象日
    var timeBand: TimeBand
    var level: AttendanceLevel
    var isEvent: Bool               // イベント（募集）かどうか
    var eventDeadline: Date?        // イベントの締め切り（任意）
    var isPresence: Bool            // 「今ここにいます」かどうか
    var createdAt: Date
    /// この予定では自分の位置を見せない（トグルは予定フォーム内だけに置く。決定済み仕様）
    var hidesOwnLocation: Bool = false

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 「今ここ」は取得から2時間で自動的に消える（決定済み仕様）
    var isExpiredPresence: Bool {
        isPresence && Date().timeIntervalSince(createdAt) > 2 * 60 * 60
    }
}
