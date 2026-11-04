import SwiftUI

/// バナー1件分（広告 or イベント告知）
struct BannerItem: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
}

/// 広告／イベント告知バナー（地図・カレンダー画面の上部に置く細い枠）
/// 仕様：
/// - レイアウトフロー内・固定高（30pt）・小さめで、操作の邪魔にならない。地図のカメラには一切触らない。
/// - 中身は直近のイベント告知＋広告プレースホルダを、数秒ごとに切り替える回転表示。
///   同じ枠で広告とイベント告知の両方を流す前提の作りにしてある。
/// - 切り替えはタイマーを張らず、表示中だけ生きる .task で回す（消えれば自動で止まる）。
struct InfoBannerView: View {
    let items: [BannerItem]
    @State private var index = 0

    var body: some View {
        ZStack {
            if !items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: current.systemImage)
                        .foregroundStyle(.orange)
                    Text(current.text)
                        .lineLimit(1)
                }
                .font(.caption)
                .id(index)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            LinearGradient(colors: [Color.orange.opacity(0.16), Color.pink.opacity(0.10)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    index = (index + 1) % items.count
                }
            }
        }
    }

    private var current: BannerItem {
        items[min(index, items.count - 1)]
    }

    /// 直近のイベント告知（最大2件）＋広告プレースホルダで枠の中身を組む。
    /// イベントが無い時は告知枠のプレースホルダも流す。
    static func items(upcomingEvents: [Plan]) -> [BannerItem] {
        var result: [BannerItem] = []
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d（E）"
        for plan in upcomingEvents.prefix(2) {
            let place = plan.placeName.isEmpty ? "場所未定" : plan.placeName
            result.append(BannerItem(text: "\(f.string(from: plan.date)) \(place)でイベント（募集）",
                                     systemImage: "party.popper"))
        }
        result.append(BannerItem(text: "広告スペース", systemImage: "megaphone"))
        if upcomingEvents.isEmpty {
            result.append(BannerItem(text: "イベント告知スペース", systemImage: "calendar.badge.clock"))
        }
        return result
    }
}
