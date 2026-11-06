import Foundation
import CoreLocation
import Observation
import SwiftLocation

/// 現在地の取得（SwiftLocation 6.x 経由。フェーズIで CoreLocation 直叩きから移行）
///
/// 決定済み仕様：
/// - 位置は「勝手に出る」ことが禁止。本人が操作して置いた時だけ表示する。
/// - 「今ここ」の保持は PlanStore 側（isPresence の予定として保存し、2時間で自動消去）。
///   「今ここ」は本人が地図のボタンを押して置いた時だけ動き、位置情報への
///   自動追従はしない（フェーズQレビュー R7 で確定）。ここは現在地の取得だけを担う。
/// - 非表示モード中は取得自体を止める（「今ここ」の取り消しは地図側が PlanStore で行う）。
/// - 地図の中心を勝手に動かさない（初回表示と現在地ボタンの時だけ）。
///
/// バッテリー方針：
/// - 常時高精度GPSは回さない。フォアグラウンドは精度10m級（nearestTenMeters）の継続取得、
///   バックグラウンド／アプリ終了後の再開は「有意な位置変化（significant-change）」ベース。
///   大きな移動があった時だけシステムに起こされ、現在地が更新される
///   （「今ここ」自体は自動では動かない）。
/// - バックグラウンドで実際に反映され得るのは「常に許可（Always）」の時だけ。
///   「アプリ使用中のみ（WhenInUse）」では開いている間に限られる
///   （設定画面にもその状態を正直に表示する。許可導線は段階式：
///   まず WhenInUse を取り、格上げは本人が設定画面から requestAlwaysUpgrade を押した時だけ）。
@Observable
final class LocationService {
    private(set) var currentFix: CLLocation?
    private(set) var fixDate: Date?
    /// 現在の位置情報の許可状態。設定画面で現状を表示するために公開する。
    private(set) var authorizationStatus: CLAuthorizationStatus

    var hideMode: Bool = false {
        didSet { if hideMode { stop() } }
    }

    /// 新しい位置が適用されるたびに呼ばれるフック。
    /// 現在は「今ここ」の自動追従には使っていない（R7：配置は手動のみが仕様で、
    /// RootView は PlanStore へ繋がない）。将来の明示的な用途のためにフック自体は残す。
    @ObservationIgnored var onLocationFix: ((CLLocation) -> Void)?

    @ObservationIgnored private let location: Location
    @ObservationIgnored private var continuousTask: Task<Void, Never>?
    @ObservationIgnored private var significantTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?

    /// - Parameter location: SwiftLocation の本体。DEBUG ではモックマネージャを
    ///   差し替えたものを注入できる（MockLocationManager.swift 参照）。
    init(location: Location = Location(allowsBackgroundLocationUpdates: true)) {
        self.location = location
        self.authorizationStatus = location.authorizationStatus
        // バッテリー配慮：最高精度の常時取得はしない。10m級でドッグラン規模には十分。
        location.accuracy = .nearestTenMeters
        startAuthorizationMonitoring()
        // 前回までに許可済みなら、起動した時点で有意な位置変化の監視を自動で再開する。
        // アプリがバックグラウンド再開で起動した時もここを通るのが、終了後再開の土台。
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startSignificantMonitoring()
        }
    }

    deinit {
        continuousTask?.cancel()
        significantTask?.cancel()
        authorizationTask?.cancel()
    }

    // MARK: - 公開API

    /// まず「アプリ使用中のみ（WhenInUse）」を依頼し、継続取得と
    /// 有意な位置変化の監視を始める。いきなり「常に許可」は求めない。
    func requestPermissionAndStart() {
        guard !hideMode else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.location.authorizationStatus == .notDetermined {
                _ = try? await self.location.requestPermission(.whenInUse)
                self.authorizationStatus = self.location.authorizationStatus
            }
            self.startMonitoring()
        }
    }

    /// 「常に許可（Always）」への格上げを依頼する（設定画面のボタンから呼ぶ）。
    /// 取れたかどうかは authorizationStatus 側で判断して表示する
    /// （取れていないのに「バックグラウンドで動く」とは表示しない）。
    func requestAlwaysUpgrade() async {
        guard !hideMode else { return }
        _ = try? await location.requestPermission(.always)
        authorizationStatus = location.authorizationStatus
        startSignificantMonitoring()
    }

    /// 「常に許可」＝アプリを閉じている間も大きな移動を拾って現在地を
    /// 更新できる状態かどうか（「今ここ」は自動では動かない）
    var isBackgroundReflectionAvailable: Bool {
        authorizationStatus == .authorizedAlways
    }

    func stop() {
        continuousTask?.cancel()
        continuousTask = nil
        significantTask?.cancel()
        significantTask = nil
        location.stopUpdatingLocation()
        location.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - 監視の開始

    private func startMonitoring() {
        guard !hideMode else { return }
        startContinuousMonitoring()
        startSignificantMonitoring()
    }

    /// フォアグラウンド用：アプリを開いている間の継続取得（精度10m級）。
    private func startContinuousMonitoring() {
        guard continuousTask == nil else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        continuousTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.location.startMonitoringLocations()
                for await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .didUpdateLocations(let locations):
                        if let last = locations.last { self.applyFix(last) }
                    case .didFailed, .didPaused, .didResume:
                        // 失敗しても画面は壊さない。現在地なし＝日本全体表示の
                        // フォールバックはView側で判断（従来どおり）。
                        break
                    }
                }
            } catch {
                // 開始できなかった場合も画面は壊さない
            }
            self.continuousTask = nil
        }
    }

    /// バックグラウンド／終了後再開用：有意な位置変化（大きな移動）だけを拾う。
    /// 実際にアプリが起こされるのは「常に許可」の時。それ以外では開いている間の補助になる。
    private func startSignificantMonitoring() {
        guard !hideMode, significantTask == nil else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        significantTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.location.startMonitoringSignificantLocationChanges()
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .didUpdateLocations(let locations):
                    if let last = locations.last { self.applyFix(last) }
                case .didFailWithError, .didPaused, .didResume:
                    break
                }
            }
            self.significantTask = nil
        }
    }

    /// 許可状態の変化を追って公開プロパティへ反映する。
    /// 端末の設定アプリで許可が変わった場合なども、取れた時点で監視を自動で始める。
    private func startAuthorizationMonitoring() {
        guard authorizationTask == nil else { return }
        authorizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.location.startMonitoringAuthorization()
            for await event in stream {
                if Task.isCancelled { break }
                self.authorizationStatus = event.authorizationStatus
                if event.authorizationStatus == .authorizedWhenInUse
                    || event.authorizationStatus == .authorizedAlways {
                    self.startMonitoring()
                }
            }
        }
    }

    // MARK: - 位置の適用

    private func applyFix(_ newFix: CLLocation) {
        guard !hideMode else { return }
        // 静止時のGPS揺らぎで画面全体を作り直さない：
        // 前回適用から25m以上動いた時か、2分経った時だけ反映する（プロトタイプの修正を踏襲）
        if let prev = currentFix, let prevDate = fixDate,
           newFix.distance(from: prev) < 25,
           Date().timeIntervalSince(prevDate) < 120 {
            return
        }
        currentFix = newFix
        fixDate = Date()
        onLocationFix?(newFix)
    }
}
