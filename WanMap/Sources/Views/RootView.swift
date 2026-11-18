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
                                           nextLabel: "地図へ移動 >>",
                                           previousLabel: nil,
                                           onNext: { moveTab(by: 1) },
                                           onPrevious: { moveTab(by: -1) }))
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            DogMapView()
                .modifier(TabSwipeModifier(edgeOnly: true,
                                           nextLabel: nil,
                                           previousLabel: "<< カレンダーへ移動",
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
/// 第3ラウンド項目4の試作として「カーテン方式」に作り替えた（2026-11-18、本人の発案）：
/// 遷移先の実画面を指に追従させる代わりに、現在の画面そのものを指でスライドさせ、
/// 普段見えない後ろの面（行き先ラベル＋恐竜ハスキー）を覗かせる。半分程度
/// スライドしたら切り替え、届かなければバネで戻る。素早いフリックは
/// 予測到達位置（predictedEndTranslation）で半分を超えるか判定する。
/// - 通常画面：横方向がはっきり勝ったドラッグだけをカーテンに使う
///   （縦スクロールやタップと取り違えないための方向ロック）。
/// - 地図（edgeOnly）：横ドラッグは地図パンそのものなので、画面の左右端
///   44pt以内から始まったドラッグだけをタブ切り替えに使う（従来どおり。
///   左端開始は右方向だけ、右端開始は左方向だけを受け付ける）。
/// - 「動きを減らす」設定時はスライドさせず、従来どおり終了時判定だけで切り替える。
/// 切り替え自体は selection の変更のみで、タブバー操作・状態保持は通常の TabView と同じ。
private struct TabSwipeModifier: ViewModifier {
    let edgeOnly: Bool
    /// 左方向スワイプ（次へ）で後ろに出るラベル。nil の方向へはスライドしない
    let nextLabel: String?
    /// 右方向スワイプ（前へ）で後ろに出るラベル
    let previousLabel: String?
    let onNext: () -> Void
    let onPrevious: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var dragLock: DragLock = .undecided

    private enum DragLock {
        case undecided, horizontal, vertical, outside
    }

    /// 背面に出す恐竜ハスキー（DecorationFooter と同じ同梱PNGを読む。
    /// 読み込めない場合はラベルだけで出す）
    private static let dinoImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "husky-dino-peek", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    #if DEBUG
    /// 画面撮影専用（-wmCurtainPreview）：カーテンを半分強開けた状態で固定表示する
    private var previewRatio: CGFloat? {
        ProcessInfo.processInfo.arguments.contains("-wmCurtainPreview") ? -0.55 : nil
    }
    #endif

    func body(content: Content) -> some View {
        if edgeOnly {
            // 地図は従来どおり GeometryReader で幅を取る（この形は従来から
            // 地図側で使われていて実績がある）
            GeometryReader { proxy in
                curtainStack(content: content, width: proxy.size.width)
            }
        } else {
            // カレンダー側は GeometryReader で包まない。カレンダー内部にも
            // GeometryReader（装飾フッターのレイアウト計算）があり、二重に
            // 包むと月スクロールの着地が1か月分ズレる回帰が CI で 2/2 再現した
            // （フロー7、run 44254780991。切り分けとして外側を外した形）
            curtainStack(content: content, width: UIScreen.main.bounds.width)
        }
    }

    private func curtainStack(content: Content, width: CGFloat) -> some View {
        let offset = effectiveOffset(width: width)
        return ZStack {
            if offset != 0 {
                curtainBackdrop(offset: offset, width: width)
            }
            content
                .offset(x: offset)
        }
        .simultaneousGesture(swipeGesture(width: width))
        .onAppear {
            // 切り替え直後に前タブ側のオフセットが残らないための保険
            if dragLock == .undecided { dragOffset = 0 }
        }
    }

    private func effectiveOffset(width: CGFloat) -> CGFloat {
        #if DEBUG
        if let previewRatio { return width * previewRatio }
        #endif
        return dragOffset
    }

    /// 後ろの面：行き先ラベル＋恐竜ハスキーを、覗いている側に寄せて置く
    @ViewBuilder
    private func curtainBackdrop(offset: CGFloat, width: CGFloat) -> some View {
        ZStack {
            WanStyle.canvas
            if offset < 0, let nextLabel {
                HStack {
                    Spacer()
                    curtainPanel(label: nextLabel, panelWidth: width * 0.55)
                }
            } else if offset > 0, let previousLabel {
                HStack {
                    curtainPanel(label: previousLabel, panelWidth: width * 0.55)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func curtainPanel(label: String, panelWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            if let dino = Self.dinoImage {
                Image(uiImage: dino)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
            }
            Text(label)
                .font(.title3.bold())
                .foregroundStyle(WanStyle.cocoa)
        }
        .frame(width: panelWidth)
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !reduceMotion else { return }
                #if DEBUG
                if previewRatio != nil { return }
                #endif
                let dx = value.translation.width
                let dy = value.translation.height
                if dragLock == .undecided {
                    if edgeOnly {
                        // 端ゾーン外から始まったドラッグは対象外（地図パンに譲る）
                        let startX = value.startLocation.x
                        guard startX <= 44 || startX >= width - 44 else {
                            dragLock = .outside
                            return
                        }
                    }
                    if abs(dy) > 14, abs(dy) > abs(dx) {
                        dragLock = .vertical
                    } else if abs(dx) > 16, abs(dx) > abs(dy) * 1.4 {
                        dragLock = .horizontal
                    } else {
                        return
                    }
                }
                guard dragLock == .horizontal else { return }
                var proposed = dx
                if proposed < 0, nextLabel == nil { proposed = 0 }
                if proposed > 0, previousLabel == nil { proposed = 0 }
                if edgeOnly {
                    // 地図：左端開始は右方向だけ、右端開始は左方向だけ
                    let startX = value.startLocation.x
                    if startX <= 44, proposed < 0 { proposed = 0 }
                    if startX >= width - 44, proposed > 0 { proposed = 0 }
                }
                dragOffset = max(-width, min(width, proposed))
            }
            .onEnded { value in
                let wasHorizontal = dragLock == .horizontal
                let offset = dragOffset
                dragLock = .undecided
                if reduceMotion {
                    // 動きを減らす設定では従来どおり、終了時の判定だけで切り替える
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 64, abs(dx) > abs(dy) * 2.2 else { return }
                    if edgeOnly {
                        let startX = value.startLocation.x
                        if dx > 0, startX > 44 { return }
                        if dx < 0, startX < width - 44 { return }
                    }
                    if dx < 0, nextLabel != nil { onNext() }
                    if dx > 0, previousLabel != nil { onPrevious() }
                    return
                }
                guard wasHorizontal, offset != 0 else {
                    dragOffset = 0
                    return
                }
                // 半分程度スライドしたら切り替え（フリックは予測到達位置で判定）
                let commitDistance = width / 2
                let predicted = value.predictedEndTranslation.width
                let commits = abs(offset) >= commitDistance
                    || (offset < 0 ? predicted <= -commitDistance : predicted >= commitDistance)
                if commits {
                    let goNext = offset < 0
                    withAnimation(.easeIn(duration: 0.16)) {
                        dragOffset = goNext ? -width : width
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(170))
                        if goNext { onNext() } else { onPrevious() }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { dragOffset = 0 }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
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
