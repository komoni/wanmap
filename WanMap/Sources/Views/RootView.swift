import SwiftUI
import UIKit
#if DEBUG
import CoreLocation
import SwiftLocation
#endif

/// ルート：カレンダーがメイン画面（最初に開く画面）、地図とイベントはタブ（決定済み仕様）
struct RootView: View {
    @State private var facilityStore = FacilityStore()
    @State private var userPlaceStore = UserPlaceStore()
    @State private var planStore: PlanStore
    @State private var friendStore = FriendStore()
    @State private var breedStore = BreedStore()
    @State private var markerSettings: MarkerSettings
    @State private var themeStore: ThemeStore
    @State private var appearanceStore: AppearanceStore
    @State private var feedbackSettings: FeedbackSettings
    @State private var feedbackService: FeedbackService
    /// サーバーアカウント（フェーズ2）。起動だけでは通信しない
    @State private var authService = AuthService()
    /// サーバー友達機能（単位2-4）。サインイン＋プロフィール確定で動き出す
    @State private var friendService = FriendService()
    @State private var location: LocationService

    #if DEBUG
    /// UIフローテスト専用（起動引数 -UITestingFlowData の時だけ使う）：
    /// モック位置マネージャ。実GPSの無いシミュレータでも「今ここ」の
    /// 操作フローを検証できるよう、.task 側で現在地を1回流し込むために保持する。
    /// 画面撮影（-UITestingSeedData のみ）では nil のままで、従来どおり実GPS経路になる。
    private let uiFlowLocationManager: MockLocationManager?
    #endif

    init() {
        // UIテスト専用の起動経路（DEBUGのみ。通常起動の実データには一切混ぜない）：
        // - -UITestingSeedData：仮想ユーザーのシード予定で起動し、撮影対象の画面に
        //   予定が見える状態にする（画面撮影用。位置は実GPS経路のまま）。
        // - -UITestingFlowData：シード予定に加えてモック現在地も使う（フロー検証用）。
        // - -UITestingPersistentPlans：隔離した永続保存先で起動する（愛ハス定例デモ用。
        //   シードと違い実ファイルへ読み書きするので、終了→再起動でも同じ予定が
        //   残ることを証明できる。-UITestingPersistentPlansReset を併せると空から始める）。
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(UITestingPersistentStore.launchArgument) {
            if arguments.contains(UITestingPersistentStore.resetArgument) {
                UITestingPersistentStore.reset()
            }
            _planStore = State(initialValue: PlanStore(
                fileURL: UITestingPersistentStore.prepareFileURL()))
        } else if arguments.contains("-UITestingSeedData") || arguments.contains("-UITestingFlowData") {
            _planStore = State(initialValue: PlanStore(samplePlans: SeedData.samplePlans()))
        } else {
            _planStore = State(initialValue: PlanStore())
        }
        if arguments.contains("-UITestingFlowData") {
            let manager = MockLocationManager()
            uiFlowLocationManager = manager
            _location = State(initialValue: LocationService(location: Location(locationManager: manager)))
        } else {
            uiFlowLocationManager = nil
            _location = State(initialValue: LocationService())
        }
        #else
        _planStore = State(initialValue: PlanStore())
        _location = State(initialValue: LocationService())
        #endif

        // デザイン・気持ちよさ第一弾のストア群。
        // 配色・ヘッダー案は、スクリーンショット撮影時だけ起動引数で強制できる
        // （DEBUGのみ。通常起動では保存された設定がそのまま効く）。
        #if DEBUG
        _appearanceStore = State(initialValue: AppearanceStore(
            launchArguments: ProcessInfo.processInfo.arguments))
        #else
        _appearanceStore = State(initialValue: AppearanceStore())
        #endif
        let feedbackSettings = FeedbackSettings()
        _feedbackSettings = State(initialValue: feedbackSettings)
        _feedbackService = State(initialValue: FeedbackService(settings: feedbackSettings))
        // チップの種類は画面撮影時だけ起動引数で強制できる（DEBUGのみ）
        #if DEBUG
        _markerSettings = State(initialValue: MarkerSettings(
            launchArguments: ProcessInfo.processInfo.arguments))
        #else
        _markerSettings = State(initialValue: MarkerSettings())
        #endif
        // テーマ（雰囲気プリセット）も画面撮影時だけ起動引数で強制できる（DEBUGのみ）
        #if DEBUG
        _themeStore = State(initialValue: ThemeStore(
            launchArguments: ProcessInfo.processInfo.arguments))
        #else
        _themeStore = State(initialValue: ThemeStore())
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 選択中のタブ（横スワイプでの切り替えにも使う。実機フィードバック④）
    @State private var selectedTab: AppTab = .calendar
    /// カーテン方式タブ切り替え（第3ラウンド項目4の試作、2026-11-18）のドラッグ量。
    /// TabView の外側（RootView）で保持し、各タブの中身には一切包みを足さない。
    /// タブの中身を ZStack 等で包む形は、カレンダーの月スクロールの着地が
    /// 1か月ズレる回帰を CI で 3/3 再現したため採らない（run 44254780991／
    /// 44262846155。包みを外す切り分けで確定したら DEV_LESSONS へ記録する）
    @State private var curtainOffset: CGFloat = 0
    @State private var curtainLock: CurtainDragLock = .undecided
    /// 地図タブでカーテンを掴める端ゾーンの幅（pt）。44から60へ広げた
    /// （実機フィードバック第3ラウンド項目5、2026-11-19。本人の端末は
    /// 画面の縁が丸く端そのものが触りにくいため、開始位置を内寄せにした）
    private static let curtainEdgeWidth: CGFloat = 60

    private enum CurtainDragLock {
        case undecided, horizontal, vertical, outside
    }

    /// 共有シートから保留された取り込み（フェーズJ）。開いたら中身は破棄済み
    @State private var sharedImport: SharedImportRequest?

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        ZStack {
            if effectiveCurtainOffset != 0 {
                curtainBackdrop(offset: effectiveCurtainOffset)
            }
            TabView(selection: $selectedTab) {
                CalendarView()
                    .tabItem { Label("カレンダー", systemImage: "calendar") }
                    .tag(AppTab.calendar)

                DogMapView()
                    .tabItem { Label("地図", systemImage: "map") }
                    .tag(AppTab.map)
            }
            .offset(x: effectiveCurtainOffset)
            .simultaneousGesture(curtainGesture)
        }
        .tint(WanStyle.coral)
        .environment(facilityStore)
        .environment(userPlaceStore)
        .environment(planStore)
        .environment(friendStore)
        .environment(breedStore)
        .environment(markerSettings)
        .environment(themeStore)
        .environment(appearanceStore)
        .environment(feedbackSettings)
        .environment(feedbackService)
        .environment(authService)
        .environment(friendService)
        .environment(location)
        .onChange(of: authService.uid) { _, _ in syncFriendService() }
        .onChange(of: authService.displayId) { _, _ in syncFriendService() }
        .task {
            syncFriendService()
            await facilityStore.refreshFromRemote()
            await breedStore.refreshFromRemote()
            // 「今ここ」は位置情報で自動的には動かさない（フェーズQレビュー R7）。
            // 配置・置き直しは本人が地図の「今ここ」ボタンを押した時だけ。
            // そのため LocationService.onLocationFix は PlanStore へ繋がない。
            location.requestPermissionAndStart()
            #if DEBUG
            // UIフローテスト専用：モック現在地（ドッグウィズ付近）を1回流し込む。
            // 監視開始後に流れるよう少し待ってから emit する。
            // -UITestingSeedData のみの起動では manager が nil なので何もしない。
            if let uiFlowLocationManager {
                try? await Task.sleep(for: .seconds(1))
                uiFlowLocationManager.emitLocation(
                    CLLocation(latitude: 35.1649375, longitude: 137.08455))
            }
            #endif
        }
        // 共有シート経由の取り込み（フェーズJ）：起動時とフォアグラウンド復帰時に
        // 保留があれば取り込み画面を開く。開く前に保留を消し、同じ文面が
        // 何度も開かないようにする（解析・保存はあくまで取り込み画面側の確認を経る）。
        .onAppear { checkSharedInbox() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkSharedInbox()
                // バックグラウンドにいる間に2時間を迎えた「今ここ」を、
                // 復帰した時点で保存データからも掃除する（表示側は常に除外済み）
                planStore.pruneExpiredPresence()
            }
        }
        .sheet(item: $sharedImport) { request in
            StoryImportView(initialText: request.text)
        }
    }

    /// サーバー友達機能の開始・停止を認証状態に合わせる（単位2-4）。
    /// uid と表示IDが揃ったら開始し、サインアウトしたら止める。
    private func syncFriendService() {
        if let uid = authService.uid, let displayId = authService.displayId {
            friendService.start(uid: uid,
                                displayId: displayId,
                                displayName: authService.serverDisplayName ?? "",
                                store: friendStore)
        } else if authService.uid == nil {
            friendService.stop()
        }
    }

    private func checkSharedInbox() {
        guard sharedImport == nil, let text = SharedImportInbox.pendingText() else { return }
        SharedImportInbox.clear()
        sharedImport = SharedImportRequest(text: text)
    }

    /// 横スワイプでのタブ移動（端のタブでは止まる。タブの並び順と対）
    private func moveTab(by delta: Int) {
        let order: [AppTab] = [.calendar, .map]
        guard let index = order.firstIndex(of: selectedTab) else { return }
        let next = index + delta
        guard order.indices.contains(next) else { return }
        selectedTab = order[next]
    }

    // MARK: - カーテン方式タブ切り替え（第3ラウンド項目4の試作、2026-11-18・本人の発案）

    /// 画面幅（タブの中身は全幅なので画面幅と一致する）
    private var curtainWidth: CGFloat { UIScreen.main.bounds.width }

    /// 左方向スワイプ（次へ）で後ろに出るラベル。無い方向へはスライドしない
    private var curtainNextLabel: String? {
        selectedTab == .calendar ? "地図へ移動 >>" : nil
    }

    /// 右方向スワイプ（前へ）で後ろに出るラベル
    private var curtainPreviousLabel: String? {
        selectedTab == .map ? "<< カレンダーへ移動" : nil
    }

    /// 地図タブでは端ゾーン開始のドラッグだけを対象にする（地図パンと競合回避）
    private var curtainEdgeOnly: Bool { selectedTab == .map }

    private var effectiveCurtainOffset: CGFloat {
        #if DEBUG
        // 画面撮影専用（-wmCurtainPreview）：カーテンを半分強開けた状態で固定表示する
        if ProcessInfo.processInfo.arguments.contains("-wmCurtainPreview") {
            return curtainWidth * -0.55
        }
        #endif
        return curtainOffset
    }

    /// 背面に出す恐竜ハスキー（DecorationFooter と同じ同梱PNGを読む。
    /// 読み込めない場合はラベルだけで出す）
    private static let curtainDinoImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "husky-dino-peek", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    /// 後ろの面：行き先ラベル＋恐竜ハスキーを、覗いている側に寄せて置く
    @ViewBuilder
    private func curtainBackdrop(offset: CGFloat) -> some View {
        ZStack {
            WanStyle.canvas
            if offset < 0, let label = curtainNextLabel {
                HStack {
                    Spacer()
                    curtainPanel(label: label)
                }
            } else if offset > 0, let label = curtainPreviousLabel {
                HStack {
                    curtainPanel(label: label)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func curtainPanel(label: String) -> some View {
        VStack(spacing: 10) {
            if let dino = Self.curtainDinoImage {
                Image(uiImage: dino)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
            }
            Text(label)
                .font(.title3.bold())
                .foregroundStyle(WanStyle.cocoa)
        }
        .frame(width: curtainWidth * 0.55)
    }

    /// 現在の画面そのものを指でスライドさせるドラッグ。半分程度スライドしたら
    /// 切り替え、届かなければバネで戻る。素早いフリックは予測到達位置
    /// （predictedEndTranslation）で半分を超えるか判定する。
    /// 「動きを減らす」設定時はスライドさせず、従来どおり終了時判定だけで切り替える。
    private var curtainGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !reduceMotion else { return }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-wmCurtainPreview") { return }
                #endif
                let width = curtainWidth
                let dx = value.translation.width
                let dy = value.translation.height
                if curtainLock == .undecided {
                    if curtainEdgeOnly {
                        // 端ゾーン外から始まったドラッグは対象外（地図パンに譲る）
                        let startX = value.startLocation.x
                        guard startX <= Self.curtainEdgeWidth
                                || startX >= width - Self.curtainEdgeWidth else {
                            curtainLock = .outside
                            return
                        }
                    }
                    if abs(dy) > 14, abs(dy) > abs(dx) {
                        curtainLock = .vertical
                    } else if abs(dx) > 16, abs(dx) > abs(dy) * 1.4 {
                        curtainLock = .horizontal
                    } else {
                        return
                    }
                }
                guard curtainLock == .horizontal else { return }
                var proposed = dx
                if proposed < 0, curtainNextLabel == nil { proposed = 0 }
                if proposed > 0, curtainPreviousLabel == nil { proposed = 0 }
                if curtainEdgeOnly {
                    // 地図：左端開始は右方向だけ、右端開始は左方向だけ
                    let startX = value.startLocation.x
                    if startX <= Self.curtainEdgeWidth, proposed < 0 { proposed = 0 }
                    if startX >= width - Self.curtainEdgeWidth, proposed > 0 { proposed = 0 }
                }
                curtainOffset = max(-width, min(width, proposed))
            }
            .onEnded { value in
                let wasHorizontal = curtainLock == .horizontal
                let offset = curtainOffset
                curtainLock = .undecided
                if reduceMotion {
                    // 動きを減らす設定では従来どおり、終了時の判定だけで切り替える
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 64, abs(dx) > abs(dy) * 2.2 else { return }
                    if curtainEdgeOnly {
                        let width = curtainWidth
                        let startX = value.startLocation.x
                        if dx > 0, startX > Self.curtainEdgeWidth { return }
                        if dx < 0, startX < width - Self.curtainEdgeWidth { return }
                    }
                    if dx < 0, curtainNextLabel != nil { moveTab(by: 1) }
                    if dx > 0, curtainPreviousLabel != nil { moveTab(by: -1) }
                    return
                }
                guard wasHorizontal, offset != 0 else {
                    curtainOffset = 0
                    return
                }
                // 半分程度スライドしたら切り替え（フリックは予測到達位置で判定）
                let width = curtainWidth
                let commitDistance = width / 2
                let predicted = value.predictedEndTranslation.width
                let commits = abs(offset) >= commitDistance
                    || (offset < 0 ? predicted <= -commitDistance : predicted >= commitDistance)
                if commits {
                    let goNext = offset < 0
                    withAnimation(.easeIn(duration: 0.16)) {
                        curtainOffset = goNext ? -width : width
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(170))
                        moveTab(by: goNext ? 1 : -1)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { curtainOffset = 0 }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        curtainOffset = 0
                    }
                }
            }
    }
}

/// タブの識別（並び順は TabView の宣言順と一致させる）。
/// イベントは旧タブを廃止し、カレンダーのボタンから開く形に統合した
/// （実機フィードバック⑩、2026-11-14）
enum AppTab: Hashable {
    case calendar, map
}

/// イベント一覧：イベント（募集）の予定だけを開催日が近い順に並べ、過去分は自動で隠す。
/// 募集への参加・承認機能は未実装（使う人が増えてからのバージョンアップで入れる想定）。
struct EventsView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(planStore.upcomingEvents()) { plan in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(WanStyle.lavender.opacity(0.55)).frame(width: 34, height: 34)
                            Text("🐶")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.placeName.isEmpty ? "場所未定" : plan.placeName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(subtitle(for: plan))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("募集への参加・承認機能は準備中です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("イベント")
            // 他の画面と揃えて右上に「閉じる」を置く
            // （実機フィードバック第4ラウンド F4、2026-11-21）
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func subtitle(for plan: Plan) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d（E）"
        var parts = [f.string(from: plan.date), plan.timeBand.rawValue, plan.level.rawValue]
        if let dog = plan.dogName, !dog.isEmpty { parts.append(dog) }
        if let deadline = plan.eventDeadline {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ja_JP")
            df.dateFormat = "M/d"
            parts.append("締切 \(df.string(from: deadline))")
        }
        return parts.joined(separator: "・")
    }
}
