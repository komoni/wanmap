import SwiftUI

/// ルート：カレンダーがメイン画面（最初に開く画面）、地図とイベントはタブ（決定済み仕様）
struct RootView: View {
    @State private var facilityStore = FacilityStore()
    @State private var location = LocationService()

    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }

            DogMapView()
                .tabItem { Label("地図", systemImage: "map") }

            EventsView()
                .tabItem { Label("イベント", systemImage: "ticket") }
        }
        .environment(facilityStore)
        .environment(location)
        .task {
            await facilityStore.refreshFromRemote()
            location.requestPermissionAndStart()
        }
    }
}

/// イベント一覧（全国／周辺の切り替え付き）。中身はプロトタイプ仕様を移植していく。
struct EventsView: View {
    var body: some View {
        Text("イベント一覧（実装中）")
    }
}
