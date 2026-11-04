import Foundation
import CoreLocation
import Observation

/// 現在地と「今ここ」の管理
///
/// 決定済み仕様：
/// - 位置は「勝手に出る」ことが禁止。本人が操作して置いた時だけ表示する。
/// - 置いた位置は2時間で自動消去。新しい位置を置いたら前の場所は消して置き換える（履歴は残さない）。
/// - 非表示モード中は取得自体を止め、保存済みの位置も消す。
/// - 地図の中心を勝手に動かさない（初回表示と現在地ボタンの時だけ）。
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var currentFix: CLLocation?
    private(set) var fixDate: Date?
    /// 本人がワンタップで置いた「今ここ」（端末内のみ保持）
    private(set) var presence: Presence?
    var hideMode: Bool = false {
        didSet { if hideMode { clearPresence(); stop() } }
    }

    struct Presence: Equatable {
        var coordinate: CLLocationCoordinate2D
        var placeName: String?  // 登録済みの場所に紐付く時だけ名前を持つ。未登録地点は人アイコンのみ
        var placedAt: Date

        static func == (lhs: Presence, rhs: Presence) -> Bool {
            lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.placeName == rhs.placeName
                && lhs.placedAt == rhs.placedAt
        }
    }

    private let manager = CLLocationManager()
    private var expiryTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionAndStart() {
        guard !hideMode else { return }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// 「今ここ」を置く（ワンタップ）。置き直したら前の場所は消える。
    func placePresence(at coordinate: CLLocationCoordinate2D, placeName: String?) {
        guard !hideMode else { return }
        presence = Presence(coordinate: coordinate, placeName: placeName, placedAt: Date())
        scheduleExpiry()
    }

    func clearPresence() {
        presence = nil
        expiryTimer?.invalidate()
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 2 * 60 * 60, repeats: false) { [weak self] _ in
            self?.clearPresence()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        // 静止時のGPS揺らぎで画面全体を作り直さない：
        // 前回適用から25m以上動いた時か、2分経った時だけ反映する（プロトタイプの修正を踏襲）
        if let prev = currentFix, let prevDate = fixDate,
           last.distance(from: prev) < 25,
           Date().timeIntervalSince(prevDate) < 120 {
            return
        }
        currentFix = last
        fixDate = Date()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 失敗しても画面は壊さない。現在地なし＝日本全体表示のフォールバックはView側で判断。
    }
}
