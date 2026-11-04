import Foundation
import CoreLocation
import Observation

/// 現在地の取得
///
/// 決定済み仕様：
/// - 位置は「勝手に出る」ことが禁止。本人が操作して置いた時だけ表示する。
/// - 「今ここ」の保持は PlanStore 側（isPresence の予定として保存し、2時間で自動消去、
///   移動したら新しい位置に置き換える）。ここは現在地の取得だけを担う。
/// - 非表示モード中は取得自体を止める（「今ここ」の取り消しは地図側が PlanStore で行う）。
/// - 地図の中心を勝手に動かさない（初回表示と現在地ボタンの時だけ）。
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var currentFix: CLLocation?
    private(set) var fixDate: Date?
    var hideMode: Bool = false {
        didSet { if hideMode { stop() } }
    }

    private let manager = CLLocationManager()

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
