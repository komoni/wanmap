import ClusterMap
import ClusterMapSwiftUI
import SwiftUI
import MapKit

/// 地図タブ
/// 仕様：
/// - 初期表示は現在地優先。取れない時だけ日本全体（フォールバックは初回だけ）。
/// - 操作中に中心を勝手に戻さない。寄せるのは初回・現在地ボタン・友達レールタップ・検索候補タップの時だけ。
/// - 施設マーカーは ClusterMap でクラスタリングする：引いた表示では密集地点を件数バッジに集約し、
///   拡大すると個別マーカーに戻る。個別マーカーはズームで切替：引いた表示は 🐶（ラン）／☕（カフェ）のみ、
///   拡大（ズーム13以上）で施設名も。クラスタは施設名が出るズームより手前で必ず解けるよう、
///   ClusterMap 側の maxZoomLevel を 12 にしている（ClusterMap の内部ズームは端末幅で本アプリ換算より
///   約0.6〜2 大きくなるため、12 でも解ける地点はズーム13未満に収まる）。
///   予定アイコンと「今ここ」はクラスタリング対象にしない。
/// - 予定アイコンは選択中の日付＋時間帯で絞り込んで小さく出す（施設名を隠さない大きさ）。場所名は出さない。
///   アイコンはゆっくり浮遊し、地図をタッチしている間は指の周辺のものが指から逃げ、離すとゆっくり戻る
///   （Webプロトタイプで実機確認済みの動きの iOS 版）。逃げる動きは地図本体と同時認識の観察専用ジェスチャで
///   指位置だけを拾い、タッチ位置に連動するオフセットで表現するので、ドラッグ／ピンチは妨げない。
/// - 上部には広告／イベント告知バナー（InfoBannerView）をレイアウトフロー内に置く。地図領域が狭まるだけで
///   カメラには触らない。
/// - 「今ここ」は日付・時間帯に関係なく常時表示。PlanStore に isPresence の予定として保持する（2時間で自動消去、移動したら置き換え）。
/// - 日付切替はボタン式（横スクロール、今日から84日分）＋時間帯ボタン（終日／朝／昼／夜）。
///   地図が主役のため、この2つは地図の下（画面下部・タブバーの上）に置き、地図領域を最大化する。
///   選択中の日付はユーザー操作でのみ変わる。タイマー・位置取得・再表示などで勝手に戻す処理は置かない（強制リバート禁止）。
/// - 友達レール（右端）：予定／presence を持つ人の小さなアイコン。タップでその人の地点へズーム15で飛ぶ。
/// - 施設検索：候補タップではシートを開かず、ズーム15で地点へ寄るだけ。シートはマーカー／施設名タップの時だけ。
/// - 地点登録：上部バーの＋から入る。地図の中心ピンで地点を決める方式（開始・終了でカメラは動かさない）。
///   追加した場所（UserPlace）は公式施設とは別枠で端末内に持ち、表示・検索では施設より優先して扱う。
///   公開範囲のデフォルトは「招待した人だけ」で、共有されるのは場所名のみ（座標は公開しない）。
/// - ベースマップの飲食店などのPOIは出さない。
struct DogMapView: View {
    @Environment(FacilityStore.self) private var store
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(PlanStore.self) private var planStore
    @Environment(LocationService.self) private var location
    @State private var position: MapCameraPosition = .japanFallback
    @State private var selectedFacility: Facility?
    @State private var selectedUserPlace: UserPlace?

    // 地点登録モード（中心ピン）。入る時・出る時もカメラには触らない。
    @State private var isPlacingUserPlace = false
    @State private var pendingPlaceCoordinate: CLLocationCoordinate2D?
    @State private var showUserPlaceForm = false
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var isZoomedIn = false
    @State private var didCenterInitially = false
    @State private var statusMessage: String?
    @State private var statusTask: Task<Void, Never>?

    // 日付ストリップの状態。selectedDate を書き換えるのは日付ボタンと年ジャンプだけ
    // （onAppear／onChange／タイマーは一切触らない＝選択が勝手に戻る経路が無い）。
    @State private var days: [Date]
    @State private var selectedDate: Date
    @State private var selectedBand: TimeBand = .allDay
    @State private var showYearSheet = false
    @State private var pendingScrollDate: Date?

    // 施設検索
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // 予定アイコンの「指から逃げる」オフセット（plan.id → 画面上のずらし量）。
    // 指を離したら空に戻し、各アイコン側の spring でゆっくり戻す。
    @State private var fleeOffsets: [UUID: CGSize] = [:]

    // 施設クラスタリング（ClusterMap）。計算は ClusterManager（actor）に任せ、
    // 差分だけを visibleFacilities / visibleClusters に反映する（Example-SwiftUI の方式）。
    @State private var clusterManager = ClusterManager<FacilityAnnotation>(
        configuration: ClusterManager<FacilityAnnotation>.Configuration(maxZoomLevel: 12)
    )
    @State private var visibleFacilities: [FacilityAnnotation] = []
    @State private var visibleClusters: [FacilityCluster] = []
    @State private var mapSize: CGSize = .zero
    /// クラスタ計算に使う現在リージョン。カメラ確定時と明示操作（center／fly／zoomIn）でだけ更新する。
    @State private var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.0),
        span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
    )

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        _days = State(initialValue: (0..<84).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: today)
        })
        _selectedDate = State(initialValue: today)
    }

    /// 座標のある施設だけをマーカーにする
    private var pinnedFacilities: [Facility] {
        store.facilities.filter { $0.coordinate != nil }
    }

    /// クラスタリング用アノテーション（IDだけ保持）→ 施設本体への引き当て（名前表示・シート用）
    private var facilityById: [String: Facility] {
        Dictionary(pinnedFacilities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 地図に出す予定：「今ここ」（常時）＋選択中の日付・時間帯に合う予定のうち座標があるもの。
    /// 時間帯が「終日」の予定は、どの時間帯を選んでも出す。
    private var mapPlans: [Plan] {
        planStore.activePlans.filter { plan in
            guard plan.coordinate != nil else { return false }
            if plan.isPresence { return true }
            guard Calendar.current.isDate(plan.date, inSameDayAs: selectedDate) else { return false }
            return selectedBand == .allDay || plan.timeBand == .allDay || plan.timeBand == selectedBand
        }
    }

    /// 友達レールに出す人：座標のある予定／presence を持つ人（personName 単位、端末内データのみ）。
    /// 飛び先は presence があればその座標、無ければ今日以降で一番近い予定の座標（全部過去なら一番新しい予定）。
    private var mapPeople: [MapPerson] {
        let withCoord = planStore.activePlans.filter { $0.coordinate != nil }
        let grouped = Dictionary(grouping: withCoord, by: { $0.personName })
        let today = Calendar.current.startOfDay(for: Date())
        return grouped.compactMap { name, plans -> MapPerson? in
            let presence = plans.first { $0.isPresence }
            let targetPlan = presence
                ?? plans.filter { $0.date >= today }.min(by: { $0.date < $1.date })
                ?? plans.max(by: { $0.date < $1.date })
            guard let targetPlan, let coord = targetPlan.coordinate else { return nil }
            return MapPerson(personName: name,
                             label: String((targetPlan.dogName ?? name).prefix(1)),
                             hasPresence: presence != nil,
                             target: coord)
        }
        .sorted {
            ($0.hasPresence ? 0 : 1, $0.personName) < ($1.hasPresence ? 0 : 1, $1.personName)
        }
    }

    /// 検索候補：正規化検索でヒットした地点（タップで飛ぶため座標があるものだけ）。
    /// 自分で追加した場所を公式施設より優先して先に出す（決定済み仕様）。
    private var searchResults: [PlaceHit] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let places = userPlaceStore.search(searchText).map(PlaceHit.userPlace)
        let facilities = store.search(searchText)
            .filter { $0.coordinate != nil }
            .map(PlaceHit.facility)
        return Array((places + facilities).prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 広告／イベント告知バナー（フロー内・固定高。地図のカメラには影響しない）
            InfoBannerView(items: InfoBannerView.items(upcomingEvents: planStore.upcomingEvents()))
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
            topBar
            searchBar
            // 地図が主役なので、日付ストリップと時間帯は地図の下（画面下部）に置き、
            // 地図が残りの領域を最大限使う構成にする（ユーザーの指示、2026-11-05）。
            ZStack {
                MapReader { proxy in
                    mapView(proxy: proxy)
                }
                friendRail
                if isPlacingUserPlace {
                    placingOverlay
                }
                if !searchResults.isEmpty && !isPlacingUserPlace {
                    searchResultsList
                }
                if let statusMessage {
                    VStack {
                        Spacer()
                        Text(statusMessage)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 10)
                    }
                }
            }
            dateStrip
            bandRow
        }
        .sheet(isPresented: $showYearSheet) {
            yearSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFriends) { FriendsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $selectedUserPlace) { place in
            UserPlaceSheet(place: place)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showUserPlaceForm) {
            if let coordinate = pendingPlaceCoordinate {
                UserPlaceFormView(editing: nil, coordinate: coordinate)
            }
        }
    }

    private func mapView(proxy: MapProxy) -> some View {
        Map(position: $position) {
            // 施設マーカー（ClusterMap で計算した表示分だけ。密集時はクラスタに集約される）
            // ※タイトルに施設名を入れると、ズーム13以上で名前カプセルと二重表示になるため空にする
            //   （クラスタ側で確認済みの事象。名前表示は facilityMarker 内のカプセルが担う）
            ForEach(visibleFacilities) { item in
                if let facility = facilityById[item.id] {
                    Annotation("", coordinate: item.coordinate) {
                        Button {
                            selectedFacility = facility
                        } label: {
                            facilityMarker(facility)
                        }
                        .accessibilityLabel(facility.displayName)
                    }
                }
            }
            // 施設クラスタ（件数バッジ）。タップで少し寄せる
            // ※タイトルに件数を入れると、その文字列がアノテーション下部に
            //   テキストラベルとしても描画され、バッジ内の数字と二重表示になる。
            //   タイトルは空にし、件数はバッジ内だけに出す（読み上げ用は
            //   clusterMarker 側の accessibilityLabel で担保する）。
            ForEach(visibleClusters) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    clusterMarker(cluster)
                }
            }
            // 自分で追加した場所（公式施設とは別枠。件数が少ないのでクラスタリングしない）
            // ※タイトルは施設と同じ理由で空にする（名前は userPlaceMarker 内のカプセルが担う）
            ForEach(userPlaceStore.places) { place in
                Annotation("", coordinate: place.coordinate) {
                    Button {
                        selectedUserPlace = place
                    } label: {
                        userPlaceMarker(place)
                    }
                    .accessibilityLabel(place.name)
                }
            }
            // 予定アイコン（選択中の日付・時間帯の予定＋「今ここ」）。タイトルは出さずアイコンだけ。
            // クラスタリング対象にはしない（従来どおり個別表示）。
            ForEach(mapPlans) { plan in
                Annotation(plan.placeName, coordinate: plan.coordinate!) {
                    planMarker(plan)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        // 指位置の観察専用（地図本体のジェスチャと同時認識させるので、ドラッグ／ピンチは妨げない）
        .simultaneousGesture(fleeGesture(proxy: proxy))
        .readSize(onChange: { newSize in
            // ClusterMap の計算には地図の実サイズが要る（ClusterMapSwiftUI の .readSize）
            mapSize = newSize
            if newSize.width > 0 { requestClusterReload() }
        })
        .task {
            await syncClusterAnnotations()
        }
        .onChange(of: store.facilities) { _, _ in
            // 施設データが差し替わったら（リモート更新など）クラスタ側にも入れ直す
            Task { await syncClusterAnnotations() }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            currentRegion = context.region
            // ズーム13以上で施設名も表示する（プロトタイプの閾値13を踏襲）。
            // region の経度幅からズームレベルを換算する。
            let delta = context.region.span.longitudeDelta
            isZoomedIn = delta > 0 && log2(360 / delta) >= 13
            requestClusterReload()
        }
        .onAppear {
            // 初回表示だけ現在地へ寄せる（取れていなければ日本全体のまま）
            if !didCenterInitially, let fix = location.currentFix {
                center(on: fix.coordinate)
                didCenterInitially = true
            }
        }
        .onChange(of: location.fixDate) { _, _ in
            guard let fix = location.currentFix else { return }
            if !didCenterInitially {
                center(on: fix.coordinate)
                didCenterInitially = true
            }
            // 移動したら「今ここ」も新しい位置に置き換える（前の場所は残さない）
            planStore.moveOwnPresence(latitude: fix.coordinate.latitude,
                                      longitude: fix.coordinate.longitude)
        }
        .onChange(of: location.hideMode) { _, hidden in
            // 非表示モードになったら配置済みの「今ここ」も取り消す
            if hidden { planStore.clearOwnPresence() }
        }
        .sheet(item: $selectedFacility) { facility in
            FacilitySheet(facility: facility)
                .presentationDetents([.medium, .large])
        }
    }

    /// 施設マーカー：引いた表示は絵文字のみ、拡大時は施設名も（名前タップでもシートが開く）
    private func facilityMarker(_ facility: Facility) -> some View {
        VStack(spacing: 0) {
            Text(facility.isDogRun ? "🐶" : "☕")
                .font(.title3)
            if isZoomedIn {
                Text(facility.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Capsule())
            }
        }
    }

    /// 施設クラスタ：件数バッジ（ClusterMap 標準に近い見た目）。タップでその地点へ少し寄せる
    private func clusterMarker(_ cluster: FacilityCluster) -> some View {
        Button {
            zoomIn(on: cluster.coordinate)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                Text("\(cluster.count)")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cluster.count)件")
    }

    /// 自分の場所のマーカー：施設と同じ流儀（引いた表示は絵文字のみ、拡大時は名前も）
    private func userPlaceMarker(_ place: UserPlace) -> some View {
        VStack(spacing: 0) {
            Text(place.kind.markerEmoji)
                .font(.title3)
            if isZoomedIn {
                Text(place.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Capsule())
            }
        }
    }

    /// 予定アイコン：施設名を隠さない小さな丸（浮遊＋指から逃げる動き付きは FloatingPlanMarker 側）
    private func planMarker(_ plan: Plan) -> some View {
        FloatingPlanMarker(plan: plan,
                           isOwn: plan.id == planStore.ownPresence?.id,
                           fleeOffset: fleeOffsets[plan.id] ?? .zero)
    }

    /// 指位置の観察専用ジェスチャ。地図本体のジェスチャと同時認識させるため、
    /// ドラッグ／ピンチ／アノテーションのタップは妨げない。指の動きに合わせて
    /// 周辺アイコンの逃げオフセットを更新し、離れたら空に戻す（戻りはアイコン側の spring 任せ）。
    private func fleeGesture(proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                updateFleeOffsets(proxy: proxy, touch: value.location)
            }
            .onEnded { _ in
                fleeOffsets = [:]
            }
    }

    /// 指の周辺（半径90pt以内）にある予定アイコンについて、指から離れる方向へのオフセットを計算する。
    /// 座標→画面位置の変換は MapProxy（地図のローカル座標＝ジェスチャの .local と同空間）。
    private func updateFleeOffsets(proxy: MapProxy, touch: CGPoint) {
        let radius: CGFloat = 90
        var offsets: [UUID: CGSize] = [:]
        for plan in mapPlans {
            guard let coordinate = plan.coordinate,
                  let point = proxy.convert(coordinate, to: .local) else { continue }
            let dx = point.x - touch.x
            let dy = point.y - touch.y
            let distance = hypot(dx, dy)
            guard distance < radius else { continue }
            // 指に近いほど大きく逃げる（最大44pt）
            let strength = (1 - distance / radius) * 44
            let angle: CGFloat
            if distance > 0.5 {
                angle = atan2(dy, dx)
            } else {
                // 指の真下で方向が定まらない時は、アイコンごとに決まった方向へ逃がす
                angle = CGFloat(abs(plan.id.hashValue % 360)) * .pi / 180
            }
            offsets[plan.id] = CGSize(width: cos(angle) * strength, height: sin(angle) * strength)
        }
        fleeOffsets = offsets
    }

    private var topBar: some View {
        // 現在地／取得時刻／今ここ（取消に切替）／地点登録 を1段に（プロトタイプの最終形）
        HStack(spacing: 8) {
            Button {
                if let fix = location.currentFix {
                    center(on: fix.coordinate)
                    didCenterInitially = true
                }
            } label: {
                Image(systemName: "location.fill")
            }
            if let date = location.fixDate {
                Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                togglePresence()
            } label: {
                Text(planStore.ownPresence == nil ? "今ここ" : "取消")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                // 地点登録モードに入る（中心ピンで地点を決める。カメラは動かさない）
                isPlacingUserPlace = true
            } label: {
                Image(systemName: "plus")
            }

            Button { showFriends = true } label: {
                Image(systemName: "person.2")
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }

    // MARK: - 地点登録（中心ピン）

    /// 登録モード中の重ね表示：中心ピン（当たり判定なし）＋下部の確定バー。
    /// ピン先端が画面中心に来るよう少し上にずらす。地図のドラッグはそのまま効く。
    private var placingOverlay: some View {
        ZStack {
            Image(systemName: "mappin")
                .font(.system(size: 38))
                .foregroundStyle(.red)
                .shadow(radius: 2)
                .offset(y: -19)
                .allowsHitTesting(false)
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button("キャンセル") { isPlacingUserPlace = false }
                        .buttonStyle(.bordered)
                    Button("ここにする") { confirmPlacing() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    /// 中心ピンの地点（現在のリージョン中心）を確定し、追加フォームを開く。
    /// カメラ自体は動かさない（開始・終了で中心／ズームを変えない方針）。
    private func confirmPlacing() {
        pendingPlaceCoordinate = currentRegion.center
        isPlacingUserPlace = false
        showUserPlaceForm = true
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        currentRegion = region
        position = .region(region)
    }

    /// 明示操作専用：ズーム15相当まで寄せる（友達レール・検索候補のタップ時だけ呼ぶ）
    private func fly(to coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.011, longitudeDelta: 0.011))
        currentRegion = region
        position = .region(region)
    }

    /// 明示操作専用：クラスタタップで現在の表示幅の約4割まで寄せる（下限はズーム15相当）
    private func zoomIn(on coordinate: CLLocationCoordinate2D) {
        let delta = max(currentRegion.span.longitudeDelta * 0.4, 0.011)
        let region = MKCoordinateRegion(center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta))
        currentRegion = region
        position = .region(region)
    }

    // MARK: - 施設クラスタリング（ClusterMap）

    /// 施設データを ClusterManager に入れ直して再計算する（初回表示とデータ差し替え時に呼ぶ）
    @MainActor
    private func syncClusterAnnotations() async {
        let annotations = pinnedFacilities.compactMap { facility in
            facility.coordinate.map { FacilityAnnotation(id: facility.id, coordinate: $0) }
        }
        await clusterManager.removeAll()
        await clusterManager.add(annotations)
        await reloadClusters()
    }

    private func requestClusterReload() {
        Task { @MainActor in await reloadClusters() }
    }

    /// 現在のリージョンと地図サイズでクラスタを再計算し、差分だけを表示へ反映する
    @MainActor
    private func reloadClusters() async {
        guard mapSize.width > 0 else { return }
        let difference = await clusterManager.reload(mapViewSize: mapSize, coordinateRegion: currentRegion)
        applyClusterChanges(difference)
    }

    @MainActor
    private func applyClusterChanges(_ difference: ClusterManager<FacilityAnnotation>.Difference) {
        for removal in difference.removals {
            switch removal {
            case .annotation(let annotation):
                visibleFacilities.removeAll { $0 == annotation }
            case .cluster(let clusterAnnotation):
                visibleClusters.removeAll { $0.id == clusterAnnotation.id }
            }
        }
        for insertion in difference.insertions {
            switch insertion {
            case .annotation(let newItem):
                visibleFacilities.append(newItem)
            case .cluster(let newItem):
                visibleClusters.append(FacilityCluster(
                    id: newItem.id,
                    coordinate: newItem.coordinate,
                    count: newItem.memberAnnotations.count
                ))
            }
        }
    }

    // MARK: - 施設検索

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("施設名で検索", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color(.secondarySystemBackground))
    }

    /// 候補リスト（地図の上端に重ねる）。タップしてもシートは開かず、地点へ飛ぶだけ。
    private var searchResultsList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(searchResults) { hit in
                    Button {
                        fly(to: hit.coordinate)
                        searchText = ""
                        searchFocused = false
                    } label: {
                        HStack {
                            Text(hit.emoji)
                            Text(hit.label).lineLimit(1)
                            Spacer()
                            if hit.isUserPlace {
                                Text("自分の場所")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if hit.id != searchResults.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.regularMaterial)
            Spacer()
        }
    }

    // MARK: - 日付ストリップ・時間帯

    /// 日付ボタン（横スクロール）＋年ボタン。地図の下（フロー内）に置くのでドラッグの邪魔にならない。
    private var dateStrip: some View {
        HStack(spacing: 4) {
            Button {
                showYearSheet = true
            } label: {
                Text("\(Calendar.current.component(.year, from: selectedDate))年")
                    .font(.caption).bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayButton(day)
                                .id(day)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    // 初回だけ今日の位置から見せる（選択状態は変えない）
                    proxy.scrollTo(selectedDate, anchor: .leading)
                }
                .onChange(of: pendingScrollDate) { _, target in
                    if let target { proxy.scrollTo(target, anchor: .leading) }
                }
            }
        }
        .padding(.horizontal, 6)
        // 高さを固定する。横ScrollViewは縦方向に伸縮可能で、固定しないと
        // VStackの余り高さを地図と分け合い、ストリップだけ縦に膨らんで
        // 地図の上に大きな白い空白ができる（実機スクリーンショットで確認）。
        .frame(height: 40)
    }

    private func dayButton(_ day: Date) -> some View {
        let cal = Calendar.current
        let selected = cal.isDate(day, inSameDayAs: selectedDate)
        let weekday = cal.component(.weekday, from: day)
        return Button {
            selectedDate = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 1) {
                Text(dayLabel(day, weekday: weekday))
                    .font(.caption)
                    .bold(selected)
                    .foregroundStyle(selected ? Color.white
                                     : weekday == 1 ? Color.red
                                     : weekday == 7 ? Color.blue
                                     : Color.primary)
                if cal.isDateInToday(day) {
                    Circle()
                        .fill(selected ? Color.white : Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.orange : Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 「11/1(月)」形式
    private func dayLabel(_ day: Date, weekday: Int) -> String {
        let cal = Calendar.current
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        return "\(cal.component(.month, from: day))/\(cal.component(.day, from: day))(\(symbols[weekday - 1]))"
    }

    /// 時間帯ボタン（終日／朝／昼／夜）
    private var bandRow: some View {
        HStack(spacing: 6) {
            ForEach(TimeBand.allCases, id: \.self) { band in
                Button {
                    selectedBand = band
                } label: {
                    Text(band.rawValue)
                        .font(.caption)
                        .bold(selectedBand == band)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedBand == band ? Color.orange : Color(.secondarySystemBackground))
                        .foregroundStyle(selectedBand == band ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    /// 年ジャンプ（最小実装）：範囲内（今日から84日）に含まれる年を選び、その年の先頭の日へ移動する
    private var yearSheet: some View {
        let cal = Calendar.current
        let years = Array(Set(days.map { cal.component(.year, from: $0) })).sorted()
        return NavigationStack {
            List(years, id: \.self) { year in
                Button {
                    // 今年は今日、それ以外の年は範囲内のその年の最初の日を選ぶ
                    if year == cal.component(.year, from: Date()) {
                        selectedDate = cal.startOfDay(for: Date())
                        pendingScrollDate = selectedDate
                    } else if let target = days.first(where: { cal.component(.year, from: $0) == year }) {
                        selectedDate = target
                        pendingScrollDate = target
                    }
                    showYearSheet = false
                } label: {
                    HStack {
                        Text("\(year)年")
                        Spacer()
                        if year == cal.component(.year, from: selectedDate) {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("年を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 友達レール

    /// 右端の縦並びアイコン（28pt）。ボタン部分だけが当たるので地図操作の邪魔にならない。
    private var friendRail: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                ForEach(mapPeople) { person in
                    Button {
                        fly(to: person.target)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(person.hasPresence ? Color.pink : Color.orange)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(radius: 1)
                            Text(person.label)
                                .font(.caption2).bold()
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 6)
    }

    private func togglePresence() {
        if planStore.ownPresence != nil {
            planStore.clearOwnPresence()
            showStatus("今ここを消しました")
            return
        }
        if location.hideMode {
            showStatus("非表示モード中は置けません")
            return
        }
        guard let fix = location.currentFix else {
            showStatus("現在地がまだ取れていません")
            return
        }
        // 場所名は付けない（人アイコンのみ）。自宅が出るのは本人が自分で置いた時だけ
        planStore.placeOwnPresence(latitude: fix.coordinate.latitude,
                                   longitude: fix.coordinate.longitude)
        showStatus("今ここを表示しました")
    }

    /// 操作結果のメッセージは約3秒で自動的に消える（決定済み仕様）
    private func showStatus(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }
}

/// 検索候補の1件（自分の場所と公式施設を1つのリストに並べるための統合型）。
/// 自分の場所を先に並べるのが優先ルールで、並び替えは呼び出し側で行う。
private enum PlaceHit: Identifiable {
    case userPlace(UserPlace)
    case facility(Facility)

    var id: String {
        switch self {
        case .userPlace(let place): return "user-\(place.id.uuidString)"
        case .facility(let facility): return "facility-\(facility.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .userPlace(let place): return place.coordinate
        case .facility(let facility): return facility.coordinate ?? CLLocationCoordinate2D()
        }
    }

    var label: String {
        switch self {
        case .userPlace(let place): return place.name
        case .facility(let facility): return facility.displayName
        }
    }

    var emoji: String {
        switch self {
        case .userPlace(let place): return place.kind.markerEmoji
        case .facility(let facility): return facility.isDogRun ? "🐶" : "☕"
        }
    }

    var isUserPlace: Bool {
        if case .userPlace = self { return true }
        return false
    }
}

/// ClusterMap に渡す施設アノテーション。Facility 本体は coordinate が読み取り専用で
/// CoordinateIdentifiable にできないため、IDと座標だけの軽量構造体にし、
/// 表示時は FacilityStore 側の本体へ引き当てる。
private struct FacilityAnnotation: CoordinateIdentifiable, Identifiable, Hashable, Sendable {
    let id: String  // Facility.id
    var coordinate: CLLocationCoordinate2D
}

/// 表示中の施設クラスタ（ClusterMap の計算結果から、表示に必要な分だけ抜き出した形）
private struct FacilityCluster: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let count: Int
}

/// 友達レールの1人分（端末内データから組み立てる。実通信はまだ無い）
private struct MapPerson: Identifiable {
    let personName: String
    let label: String                  // アイコンに出す頭文字（犬の名前優先）
    let hasPresence: Bool              // 「今ここ」が出ている人か
    let target: CLLocationCoordinate2D // タップで飛ぶ先
    var id: String { personName }
}

/// 予定アイコン：ゆっくり上下に浮遊し、指が近づくと逃げる
/// （Webプロトタイプで本人が実機確認して「完璧」と評価した仕様の iOS 版）。
/// 浮遊は repeatForever のアニメーション（レンダリング側で回るのでタイマーは持たない）。
/// 周期はアイコンごとに少しずらし、全アイコンが同期して同じ動きにならないようにする。
/// 逃げる動きは fleeOffset のオフセット＋spring で、指を離すとゆっくり元の位置へ戻る。
/// 当たり判定はアイコン本体（26pt）のみで、浮遊・逃避で当たり範囲は広げない。
private struct FloatingPlanMarker: View {
    let plan: Plan
    let isOwn: Bool
    let fleeOffset: CGSize
    @State private var bob: CGFloat = -2.5

    var body: some View {
        ZStack {
            Circle()
                .fill(isOwn ? Color.pink : Color.orange)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            if plan.isPresence {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            } else {
                Text(String((plan.dogName ?? plan.personName).prefix(1)))
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
            }
        }
        // 逃げる動き（指を離して fleeOffset が .zero に戻ると spring でゆっくり戻る）
        .offset(x: fleeOffset.width, y: fleeOffset.height)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: fleeOffset)
        // 浮遊（このオフセットは逃げ側の .animation の対象外に置き、repeatForever 側で回す）
        .offset(y: bob)
        .onAppear {
            let duration = 1.3 + Double(abs(plan.id.hashValue % 80)) / 100.0  // 1.3〜2.1秒
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                bob = 2.5
            }
        }
    }
}

extension MapCameraPosition {
    /// 現在地が取れない時のフォールバック（日本全体）。初回表示の時だけ使う。
    static var japanFallback: MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.0),
                                   span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)))
    }
}

/// 施設情報シート（項目順・ボタン構成は決定済み仕様に準拠）
struct FacilitySheet: View {
    @Environment(PlanStore.self) private var planStore
    let facility: Facility
    @State private var showPlanForm = false

    /// 構造化フィールドが1つでも入っているか（全部空なら memo 表示に切り替える従来互換）
    private var hasStructuredInfo: Bool {
        [facility.hours, facility.closed, facility.fee, facility.reservation,
         facility.mannersWear, facility.vaccine, facility.sizeLimit,
         facility.parking, facility.notes, facility.events]
            .contains { !($0 ?? "").isEmpty }
    }

    /// Googleマップ：座標があれば座標、無ければ住所で開く
    private var googleMapsURL: URL? {
        if let lat = facility.lat, let lng = facility.lng {
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
        }
        if let address = facility.address, !address.isEmpty,
           let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
        }
        return nil
    }

    /// Instagram：URLが入っていればそのまま、ユーザーネームだけならプロフィールURLにする
    private var instagramURL: URL? {
        guard let raw = facility.instagram, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        let handle = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        return URL(string: "https://www.instagram.com/\(handle)/")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(facility.displayName).font(.title3).bold()
                if let hours = facility.hours { row("営業時間", hours) }
                if let closed = facility.closed { row("定休日", closed) }
                if let fee = facility.fee { row("料金の目安", fee) }
                if let reservation = facility.reservation { row("予約", reservation) }
                if let wear = facility.mannersWear { row("マナーウェア", wear) }
                if let vaccine = facility.vaccine { row("ワクチン証明書", vaccine) }
                if let size = facility.sizeLimit { row("大型犬・サイズ制限", size) }
                if let parking = facility.parking { row("駐車場", parking) }
                if let notes = facility.notes { row("施設注意事項", notes) }
                if let events = facility.events { row("イベント・貸切情報", events) }
                if let address = facility.address { row("住所", address) }

                // 構造化フィールドが空の施設は memo を表示する（従来互換）
                if !hasStructuredInfo {
                    if let memo = facility.memo, !memo.isEmpty { row("メモ", memo) }
                    if let shopsMemo = facility.shopsMemo, !shopsMemo.isEmpty { row("店舗メモ", shopsMemo) }
                }

                HStack {
                    if let url = googleMapsURL {
                        Link("Googleマップで開く", destination: url)
                    }
                    if let url = instagramURL {
                        Link("Instagram", destination: url)
                    }
                    if let site = facility.url, let url = URL(string: site) {
                        Link("公式サイト", destination: url)
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                // スクロールした先で、この施設での予定を入れられる（座標と名前を引き継ぐ）
                Text("いつ行く予定").font(.subheadline).bold()
                Button {
                    showPlanForm = true
                } label: {
                    Label("予定を入れる", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)

                // 電話番号は表示しない（決定済み仕様）
                Text("この情報は正確でない場合があります。お出かけ前に公式サイトなどでご確認ください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let source = facility.source, let date = facility.checkedDate {
                    Text("出典：\(source)（確認日：\(date)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showPlanForm) {
            PlanFormView(editing: nil, defaultDogName: planStore.lastDogName,
                         initialFacility: facility)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }
}
