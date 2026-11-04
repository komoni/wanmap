import SwiftUI
import MapKit

/// 地図タブ
/// 仕様：
/// - 初期表示は現在地優先。取れない時だけ日本全体（フォールバックは初回だけ）。
/// - 操作中に中心を勝手に戻さない。寄せるのは初回・現在地ボタン・友達タップ・検索候補タップの時だけ。
/// - 施設マーカーはズームで切替：引いた表示は 🐶（ラン）／☕（カフェ）のみ、拡大（ズーム13以上）で施設名も。
/// - 予定アイコンは「今日の予定＋今ここ」だけを小さく出す（施設名を隠さない大きさ）。場所名は出さない。
/// - 「今ここ」は PlanStore に isPresence の予定として保持する（2時間で自動消去、移動したら置き換え）。
/// - ベースマップの飲食店などのPOIは出さない。
struct DogMapView: View {
    @Environment(FacilityStore.self) private var store
    @Environment(PlanStore.self) private var planStore
    @Environment(LocationService.self) private var location
    @State private var position: MapCameraPosition = .japanFallback
    @State private var selectedFacility: Facility?
    @State private var isZoomedIn = false
    @State private var didCenterInitially = false
    @State private var statusMessage: String?
    @State private var statusTask: Task<Void, Never>?

    /// 座標のある施設だけをマーカーにする
    private var pinnedFacilities: [Facility] {
        store.facilities.filter { $0.coordinate != nil }
    }

    /// 地図に出す予定：「今ここ」（常時）＋今日の予定のうち座標があるもの
    private var mapPlans: [Plan] {
        let calendar = Calendar.current
        return planStore.activePlans.filter { plan in
            plan.coordinate != nil && (plan.isPresence || calendar.isDateInToday(plan.date))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                map
                if let statusMessage {
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
    }

    private var map: some View {
        Map(position: $position) {
            // 施設マーカー（座標のあるものだけ）
            ForEach(pinnedFacilities) { facility in
                Annotation(facility.displayName, coordinate: facility.coordinate!) {
                    Button {
                        selectedFacility = facility
                    } label: {
                        facilityMarker(facility)
                    }
                }
            }
            // 予定アイコン（今日の予定＋「今ここ」）。タイトルは出さずアイコンだけ
            ForEach(mapPlans) { plan in
                Annotation(plan.placeName, coordinate: plan.coordinate!) {
                    planMarker(plan)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .onMapCameraChange(frequency: .onEnd) { context in
            // ズーム13以上で施設名も表示する（プロトタイプの閾値13を踏襲）。
            // region の経度幅からズームレベルを換算する。
            let delta = context.region.span.longitudeDelta
            isZoomedIn = delta > 0 && log2(360 / delta) >= 13
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

    /// 予定アイコン：施設名を隠さない小さな丸。「今ここ」は人アイコン、それ以外は犬の名前の頭文字
    private func planMarker(_ plan: Plan) -> some View {
        let isOwn = plan.id == planStore.ownPresence?.id
        return ZStack {
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
                // TODO: 地点登録フォーム
            } label: {
                Image(systemName: "plus")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        position = .region(MKCoordinateRegion(center: coordinate,
                                              span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
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
