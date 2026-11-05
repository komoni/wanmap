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
    /// 繰り返し予定の所属シリーズID（通常予定・「今ここ」はnil）
    var seriesID: UUID? = nil
    /// シリーズ内での回番号（0始まり。1回削除しても残りを再採番しない）
    var occurrenceIndex: Int? = nil
    /// 当初生成された開催日（この回だけ日付を変えても維持する）
    var originalDate: Date? = nil
    /// この回だけ個別に編集されたか
    var isSeriesException: Bool = false

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 「今ここ」は取得から2時間で自動的に消える（決定済み仕様）
    var isExpiredPresence: Bool {
        isPresence && Date().timeIntervalSince(createdAt) > 2 * 60 * 60
    }
}

extension Plan {
    private enum CodingKeys: String, CodingKey {
        case id, personName, dogName, placeName, latitude, longitude, date, timeBand, level
        case isEvent, eventDeadline, isPresence, createdAt, hidesOwnLocation
        case seriesID, occurrenceIndex, originalDate, isSeriesException
    }

    /// 旧形式との互換デコード。後から足した項目（hidesOwnLocation と繰り返し関連）は
    /// キーが欠けていても既定値で補う。既存の必須項目まで無条件に補完はしない
    /// （破損した予定を有効なものとして扱わないため）。encode は合成のまま。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        personName = try container.decode(String.self, forKey: .personName)
        dogName = try container.decodeIfPresent(String.self, forKey: .dogName)
        placeName = try container.decode(String.self, forKey: .placeName)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        date = try container.decode(Date.self, forKey: .date)
        timeBand = try container.decode(TimeBand.self, forKey: .timeBand)
        level = try container.decode(AttendanceLevel.self, forKey: .level)
        isEvent = try container.decode(Bool.self, forKey: .isEvent)
        eventDeadline = try container.decodeIfPresent(Date.self, forKey: .eventDeadline)
        isPresence = try container.decode(Bool.self, forKey: .isPresence)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        hidesOwnLocation = try container.decodeIfPresent(Bool.self, forKey: .hidesOwnLocation) ?? false
        seriesID = try container.decodeIfPresent(UUID.self, forKey: .seriesID)
        occurrenceIndex = try container.decodeIfPresent(Int.self, forKey: .occurrenceIndex)
        originalDate = try container.decodeIfPresent(Date.self, forKey: .originalDate)
        isSeriesException = try container.decodeIfPresent(Bool.self, forKey: .isSeriesException) ?? false
    }
}
