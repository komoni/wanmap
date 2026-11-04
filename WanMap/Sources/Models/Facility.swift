import Foundation
import CoreLocation

/// 施設データ（facilities.json の1件分）
/// 配信JSONと同梱JSONで共通。アプリの再審査なしに差し替えられる前提のモデル。
struct Facility: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    /// "yes" = ドッグランあり / "no" = なし（カフェ等） / "unknown"
    let dogRun: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let hours: String?
    let closed: String?
    let fee: String?
    let reservation: String?
    let mannersWear: String?
    let vaccine: String?
    let sizeLimit: String?
    let parking: String?
    let notes: String?
    let events: String?
    let memo: String?
    let shopsMemo: String?
    let phone: String?      // データとして保持するが、画面には表示しない（決定済み仕様）
    let url: String?
    let instagram: String?
    let source: String?
    let checkedDate: String?
    let updatedAt: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// 地図マーカーの種別：ドッグラン優先、無ければカフェ扱い
    var isDogRun: Bool { dogRun == "yes" }
}

/// facilities.json 全体
struct FacilityDataset: Codable {
    let dataset: String
    let version: Int
    let generatedAt: String
    let count: Int
    let facilities: [Facility]
}
