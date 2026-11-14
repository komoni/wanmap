import SwiftUI
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
    /// 選択中のタブ（横スワイプでの切り替えにも使う。実機フィードバック④）
    @State private var selectedTab: AppTab = .calendar
    /// 共有シートから保留された取り込み（フェーズJ）。開いたら中身は破棄済み
    @State private var sharedImport: SharedImportRequest?

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .modifier(TabSwipeModifier(edgeOnly: false,
                                           onNext: { moveTab(by: 1) },
                                           onPrevious: { moveTab(by: -1) }))
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            DogMapView()
                .modifier(TabSwipeModifier(edgeOnly: true,
                                           onNext: { moveTab(by: 1) },
                                           onPrevious: { moveTab(by: -1) }))
                .tabItem { Label("地図", systemImage: "map") }
                .tag(AppTab.map)
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
        .environment(location)
        .task {
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
}

/// タブの識別（並び順は TabView の宣言順と一致させる）。
/// イベントは旧タブを廃止し、カレンダーのボタンから開く形に統合した
/// （実機フィードバック⑩、2026-11-14）
enum AppTab: Hashable {
    case calendar, map
}

/// 横スワイプでタブを切り替えるジェスチャ（実機フィードバック④、2026-11-14）。
/// - 通常画面：横方向がはっきり勝ったドラッグの終了時だけ切り替える
///   （縦スクロールやタップと取り違えないための閾値）。
/// - 地図（edgeOnly）：横ドラッグは地図パンそのものなので、画面の左右端
///   44pt以内から始まったドラッグだけをタブ切り替えに使う（代案方式。
///   第2ラウンドで「端が掴みにくい」との所感を受け、28→44ptへ拡大し、
///   地図自体にも左右10ptの余白を持たせた）。
/// 切り替え自体は selection の変更のみで、タブバー操作・状態保持は通常の TabView と同じ。
private struct TabSwipeModifier: ViewModifier {
    let edgeOnly: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void

    func body(content: Content) -> some View {
        if edgeOnly {
            GeometryReader { proxy in
                content.simultaneousGesture(swipeGesture(width: proxy.size.width))
            }
        } else {
            content.simultaneousGesture(swipeGesture(width: nil))
        }
    }

    private func swipeGesture(width: CGFloat?) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // 横が縦の2.2倍を超え、64pt以上動いた時だけ「横スワイプ」とみなす
                guard abs(dx) > 64, abs(dx) > abs(dy) * 2.2 else { return }
                if let width {
                    // 地図：端から始まったドラッグだけ（左端→前へ／右端→次へ）
                    let startX = value.startLocation.x
                    if dx > 0, startX > 44 { return }
                    if dx < 0, startX < width - 44 { return }
                }
                if dx < 0 { onNext() } else { onPrevious() }
            }
    }
}

/// イベント一覧：イベント（募集）の予定だけを開催日が近い順に並べ、過去分は自動で隠す。
/// 募集への参加・承認機能は未実装（使う人が増えてからのバージョンアップで入れる想定）。
struct EventsView: View {
    @Environment(PlanStore.self) private var planStore

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
