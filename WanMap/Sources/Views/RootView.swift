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
    @State private var themeStore = ThemeStore()
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
    }

    @Environment(\.scenePhase) private var scenePhase
    /// 共有シートから保留された取り込み（フェーズJ）。開いたら中身は破棄済み
    @State private var sharedImport: SharedImportRequest?

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }

            DogMapView()
                .tabItem { Label("地図", systemImage: "map") }

            EventsView()
                .tabItem { Label("イベント", systemImage: "ticket") }
        }
        .tint(WanStyle.coral)
        .environment(facilityStore)
        .environment(userPlaceStore)
        .environment(planStore)
        .environment(friendStore)
        .environment(themeStore)
        .environment(location)
        .task {
            await facilityStore.refreshFromRemote()
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
