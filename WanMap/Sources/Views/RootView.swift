import SwiftUI

/// ルート：カレンダーがメイン画面（最初に開く画面）、地図とイベントはタブ（決定済み仕様）
struct RootView: View {
    @State private var facilityStore = FacilityStore()
    @State private var userPlaceStore = UserPlaceStore()
    @State private var planStore = PlanStore()
    @State private var friendStore = FriendStore()
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
        .environment(userPlaceStore)
        .environment(planStore)
        .environment(friendStore)
        .environment(location)
        .task {
            await facilityStore.refreshFromRemote()
            // 新しい位置が適用されるたびに「今ここ」も置き換える。
            // 地図側の onChange でも同じ呼び出しをしているが、こちらに繋ぐことで
            // 地図を開いていない時（バックグラウンドで起こされた時）でも流れる。
            // moveOwnPresence は座標が変わっていないと何もしないので二重適用にはならない。
            location.onLocationFix = { [planStore] fix in
                planStore.moveOwnPresence(latitude: fix.coordinate.latitude,
                                          longitude: fix.coordinate.longitude)
            }
            location.requestPermissionAndStart()
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
                            Circle().fill(Color.orange.opacity(0.15)).frame(width: 34, height: 34)
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
