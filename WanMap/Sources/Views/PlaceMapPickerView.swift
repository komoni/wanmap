import SwiftUI
import MapKit

/// 地図で選んだ場所（予定フォームの「地図で選ぶ」の戻り値）
struct MapPickedPlace {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 地図で場所を選ぶシート（実機フィードバック第2ラウンド、2026-11-14：
/// 新規予定追加の場所決めに「地図で検索して選ぶ」も追加する）。
/// - 地図の中心ピンで地点を決める（地図タブの地点登録と同じ流儀）
/// - 上部の検索は MapKit の実在地点検索（施設名・住所）。候補をタップすると
///   その地点へ飛び、名前が下の名前欄に入る
/// - 名前は自由に直せる。決めたら「ここにする」で座標＋名前を返す
struct PlaceMapPickerView: View {
    /// 開いた時点の初期中心（編集時は保存済み座標、無ければ現在地→名古屋駅周辺）
    let initialCoordinate: CLLocationCoordinate2D?
    let onPick: (MapPickedPlace) -> Void

    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var query: String = ""
    @State private var results: [MKMapItem] = []
    @State private var placeName: String = ""
    @State private var searchTask: Task<Void, Never>?

    init(initialCoordinate: CLLocationCoordinate2D?,
         onPick: @escaping (MapPickedPlace) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.onPick = onPick
        // 現在地は init 時点では環境から読めないため、初期値は引数→既定値で決め、
        // 現在地が取れている場合は onAppear で寄せ直す
        let start = initialCoordinate
            ?? CLLocationCoordinate2D(latitude: 35.1709, longitude: 136.8815)  // 名古屋駅
        _centerCoordinate = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if !results.isEmpty {
                    resultsList
                }
                ZStack {
                    Map(position: $position)
                        .onMapCameraChange(frequency: .onEnd) { context in
                            centerCoordinate = context.region.center
                        }
                    // 中心ピン（先端が中心に合うよう上にずらす）
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(WanStyle.coral, Color.white)
                        .shadow(color: WanStyle.cocoa.opacity(0.3), radius: 2, x: 0, y: 1)
                        .offset(y: -22)
                        .allowsHitTesting(false)
                }
                nameAndConfirm
            }
            .navigationTitle("地図で場所を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onAppear {
                // 新規で現在地が取れている時は、現在地を初期中心にする
                if initialCoordinate == nil, let fix = location.currentFix {
                    centerCoordinate = fix.coordinate
                    position = .region(MKCoordinateRegion(
                        center: fix.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("施設名・住所で検索", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(WanStyle.lavender.opacity(0.4))
        .onChange(of: query) { _, newValue in
            // 入力が落ち着いたら自動でも検索する（候補を出しやすくする）
            searchTask?.cancel()
            let text = newValue.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { results = []; return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
                runSearch()
            }
        }
    }

    private var resultsList: some View {
        List(results, id: \.self) { item in
            Button {
                let coordinate = item.placemark.coordinate
                centerCoordinate = coordinate
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                placeName = item.name ?? ""
                results = []
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name ?? "名称不明").foregroundStyle(.primary)
                    if let address = item.placemark.title {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
    }

    private var nameAndConfirm: some View {
        VStack(spacing: 10) {
            TextField("場所の名前", text: $placeName)
                .textFieldStyle(.roundedBorder)
            Button {
                let name = placeName.trimmingCharacters(in: .whitespaces)
                onPick(MapPickedPlace(name: name.isEmpty ? "仮の場所" : name,
                                      latitude: centerCoordinate.latitude,
                                      longitude: centerCoordinate.longitude))
                dismiss()
            } label: {
                Text("ここにする")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WanPrimaryButtonStyle(fill: WanStyle.coral,
                                               horizontalPadding: 14, verticalPadding: 10))
        }
        .padding(12)
        .background(WanStyle.canvas)
    }

    /// MapKit の実在地点検索（今見ている付近を優先する）
    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        let search = MKLocalSearch(request: request)
        Task {
            if let response = try? await search.start() {
                results = Array(response.mapItems.prefix(8))
            }
        }
    }
}
