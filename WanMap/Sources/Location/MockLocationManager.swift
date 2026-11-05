#if DEBUG
import Foundation
import CoreLocation
import SwiftLocation
import SwiftUI

/// SwiftLocation の `LocationManagerProtocol` を実装した DEBUG 専用モック。
///
/// 本家 SwiftLocation 同梱の MockedLocationManager はパッケージのテストターゲット内にあり
/// アプリ側からは import できないため、公開プロトコルへの差し替え口
/// （`Location(locationManager:)`）を使って同等のものを自前で用意した。
/// SwiftLocation は MIT License（https://github.com/malcommac/SwiftLocation、
/// Copyright (c) Daniele Margutti）。このファイルの構成はそのモックを参考にしている。
///
/// 使い方：実GPSの代わりに `emitLocation(_:)` で任意の座標を流し込むと、
/// SwiftLocation 経由で LocationService.currentFix が更新される。
/// 「移動したら『今ここ』が置き換わる」様子を実機なしで確認するための土台。
final class MockLocationManager: LocationManagerProtocol {
    /// delegate 呼び出しの送信元として渡すダミー（中身は使われない）
    private let dummyManager = CLLocationManager()

    weak var delegate: CLLocationManagerDelegate?

    /// 許可リクエストへの応答として返す状態（テスト都合で差し替え可能）
    var grantedWhenInUseStatus: CLAuthorizationStatus = .authorizedWhenInUse

    var authorizationStatus: CLAuthorizationStatus {
        didSet {
            guard authorizationStatus != oldValue else { return }
            delegate?.locationManagerDidChangeAuthorization?(dummyManager)
        }
    }
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var activityType: CLActivityType = .other
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters
    var allowsBackgroundLocationUpdates: Bool = false

    /// 端末の位置情報サービス自体の ON/OFF（模擬）
    var simulatedServicesEnabled: Bool = true

    private(set) var isUpdatingLocation: Bool = false
    private(set) var isMonitoringSignificantChanges: Bool = false
    private(set) var lastEmittedLocation: CLLocation?

    init(authorizationStatus: CLAuthorizationStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }

    // MARK: - LocationManagerProtocol（検証に不要なものは最小実装）

    func locationServicesEnabled() -> Bool { simulatedServicesEnabled }

    func validatePlistConfigurationOrThrow(permission: LocationPermission) throws {}
    func validatePlistConfigurationForTemporaryAccuracy(purposeKey: String) throws {}

    func requestWhenInUseAuthorization() {
        authorizationStatus = grantedWhenInUseStatus
    }

    func requestAlwaysAuthorization() {
        authorizationStatus = .authorizedAlways
    }

    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String,
                                                   completion: ((Error?) -> Void)?) {
        accuracyAuthorization = .fullAccuracy
        completion?(nil)
    }

    func startUpdatingLocation() { isUpdatingLocation = true }
    func stopUpdatingLocation() { isUpdatingLocation = false }
    func requestLocation() {
        if let lastEmittedLocation { emitLocation(lastEmittedLocation) }
    }

    func startMonitoring(for region: CLRegion) {}
    func stopMonitoring(for region: CLRegion) {}
    func startMonitoringVisits() {}
    func stopMonitoringVisits() {}

    func startMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = true }
    func stopMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = false }

    func startUpdatingHeading() {}
    func stopUpdatingHeading() {}
    func startRangingBeacons(satisfying constraint: CLBeaconIdentityConstraint) {}
    func stopRangingBeacons(satisfying constraint: CLBeaconIdentityConstraint) {}

    // MARK: - 位置の流し込み

    /// 任意の座標を「新しい現在地」として流し込む
    func emitLocation(_ newLocation: CLLocation) {
        lastEmittedLocation = newLocation
        delegate?.locationManager?(dummyManager, didUpdateLocations: [newLocation])
    }

    /// 仮想の移動：座標列を間隔を空けて順に流す。
    /// 各点が前回適用地点から25m以上離れていれば、LocationService の
    /// 揺らぎ抑制（25m／2分）を通過して順に適用される。
    func emitJourney(_ coordinates: [CLLocationCoordinate2D],
                     interval: Duration = .seconds(2)) async {
        for coordinate in coordinates {
            emitLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            try? await Task.sleep(for: interval)
        }
    }
}

extension LocationService {
    /// DEBUG用：モックマネージャ差し替え済みの LocationService とモック本体を返す。
    /// 差し替え口はこの init（`LocationService(location:)`）で、本番コードは無改造。
    static func mock(authorizationStatus: CLAuthorizationStatus = .notDetermined)
        -> (service: LocationService, manager: MockLocationManager) {
        let manager = MockLocationManager(authorizationStatus: authorizationStatus)
        let service = LocationService(location: Location(locationManager: manager))
        return (service, manager)
    }
}

/// モック位置の動作確認用ビュー（DEBUG専用プレビュー）。
/// 「次の地点へ」を押すたびに仮想の現在地が進み、LocationService.currentFix が
/// 置き換わることを実機なしで確認する。本番の「今ここ」も同じ fix の流れで
/// PlanStore.moveOwnPresence に繋がっている（RootView の onLocationFix）。
private struct LocationMockDemoView: View {
    @State private var service: LocationService
    private let manager: MockLocationManager
    @State private var stepIndex = 0

    /// ドッグウィズ（西尾）周辺を少しずつ移動する仮想ルート（各点は25m以上離れている）
    private let route: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.16494, longitude: 137.08455),
        CLLocationCoordinate2D(latitude: 35.16610, longitude: 137.09010),
        CLLocationCoordinate2D(latitude: 35.16920, longitude: 137.09520),
    ]

    init() {
        let mock = LocationService.mock()
        _service = State(initialValue: mock.service)
        manager = mock.manager
    }

    var body: some View {
        VStack(spacing: 16) {
            if let fix = service.currentFix {
                Text(String(format: "%.5f, %.5f", fix.coordinate.latitude, fix.coordinate.longitude))
                    .font(.headline.monospaced())
            } else {
                Text("現在地なし")
                    .font(.headline)
            }
            Text("許可状態: \(String(describing: service.authorizationStatus))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("次の地点へ移動") {
                let coordinate = route[min(stepIndex, route.count - 1)]
                stepIndex += 1
                manager.emitLocation(CLLocation(latitude: coordinate.latitude,
                                                longitude: coordinate.longitude))
            }
            .disabled(stepIndex >= route.count)
        }
        .padding()
        .task { service.requestPermissionAndStart() }
    }
}

#Preview("位置モック") {
    LocationMockDemoView()
}
#endif
