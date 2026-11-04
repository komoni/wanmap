import SwiftUI
import MapKit

/// 地図タブ
/// 仕様：
/// - 初期表示は現在地優先。取れない時だけ日本全体（フォールバックは初回だけ）。
/// - 操作中に中心を勝手に戻さない。寄せるのは初回・現在地ボタン・友達タップ・検索候補タップの時だけ。
/// - 施設マーカーはズームで切替：引いた表示は 🐶（ラン）／☕（カフェ）のみ、拡大で施設名も。
/// - ベースマップの飲食店などのPOIは出さない。
struct DogMapView: View {
    @Environment(FacilityStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var position: MapCameraPosition = .japanFallback
    @State private var selectedFacility: Facility?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Map(position: $position) {
                // 施設マーカー（座標のあるものだけ）
                ForEach(store.facilities.filter { $0.coordinate != nil }) { facility in
                    Annotation(facility.displayName, coordinate: facility.coordinate!) {
                        Button {
                            selectedFacility = facility
                        } label: {
                            Text(facility.isDogRun ? "🐶" : "☕")
                                .font(.title3)
                        }
                    }
                }
                // 自分の「今ここ」（本人が置いた時だけ）
                if let presence = location.presence {
                    Annotation(presence.placeName ?? "", coordinate: presence.coordinate) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.pink)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .sheet(item: $selectedFacility) { facility in
                FacilitySheet(facility: facility)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var topBar: some View {
        // 現在地／取得時刻／今ここ（取消に切替）／地点登録 を1段に（プロトタイプの最終形）
        HStack(spacing: 8) {
            Button {
                if let fix = location.currentFix {
                    position = .region(MKCoordinateRegion(center: fix.coordinate,
                                                          span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
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
                Text(location.presence == nil ? "今ここ" : "取消")
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

    private func togglePresence() {
        if location.presence != nil {
            location.clearPresence()
        } else if let fix = location.currentFix {
            // 登録済み施設の近くならその名前付き、それ以外は人アイコンのみ（名前なし）
            location.placePresence(at: fix.coordinate, placeName: nil)
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
    let facility: Facility

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

                HStack {
                    if let lat = facility.lat, let lng = facility.lng,
                       let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)") {
                        Link("Googleマップで開く", destination: url)
                    }
                    if let ig = facility.instagram, let url = URL(string: ig) {
                        Link("Instagram", destination: url)
                    }
                    if let site = facility.url, let url = URL(string: site) {
                        Link("公式サイト", destination: url)
                    }
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
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }
}
