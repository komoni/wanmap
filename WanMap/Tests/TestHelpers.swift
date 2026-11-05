import Foundation
@testable import WanMap

/// テスト用フィクスチャ：検証に使う項目だけ差し替え、残りは空で埋める

func makeFacility(name: String, displayName: String? = nil, dogRun: String = "yes") -> Facility {
    Facility(
        id: "test-\(name)", name: name, displayName: displayName ?? name, dogRun: dogRun,
        address: nil, lat: nil, lng: nil, hours: nil, closed: nil, fee: nil,
        reservation: nil, mannersWear: nil, vaccine: nil, sizeLimit: nil, parking: nil,
        notes: nil, events: nil, memo: nil, shopsMemo: nil, phone: nil, url: nil,
        instagram: nil, source: nil, checkedDate: nil, updatedAt: nil
    )
}

func makeUserPlace(name: String, latitude: Double = 35.0, longitude: Double = 137.0) -> UserPlace {
    UserPlace(id: UUID(), name: name, kind: .dogRun, address: nil,
              latitude: latitude, longitude: longitude, memo: nil, createdAt: Date())
}

func makePlan(placeName: String = "ドッグウィズ",
              date: Date = Date(),
              isPresence: Bool = false,
              createdAt: Date = Date()) -> Plan {
    Plan(id: UUID(), personName: "テスト", dogName: nil, placeName: placeName,
         latitude: nil, longitude: nil, date: date, timeBand: .allDay, level: .going,
         isEvent: false, eventDeadline: nil, isPresence: isPresence, createdAt: createdAt)
}
