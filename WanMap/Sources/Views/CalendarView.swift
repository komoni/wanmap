import SwiftUI

/// 犬専用カレンダー（メイン画面）
/// 仕様：柔らかいパステル、日曜コーラル／土曜スカイ、今日はアクセント丸＋小さな肉球。
/// 各日はアイコン＋場所名だけ（件数や空状態メッセージは出さない）。月／年 切り替えあり。
struct CalendarView: View {
    @State private var displayedMonth: Date = Date()
    @State private var showYear = false
    @State private var selectedDay: Date?

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = 1  // 日曜始まりで固定（端末設定でズレないように）
        return c
    }()

    var body: some View {
        VStack(spacing: 8) {
            header
            if showYear {
                yearGrid
            } else {
                VStack(spacing: 6) {
                    weekdayHeader
                    monthGrid
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack {
            Button("今日") { displayedMonth = Date(); showYear = false }
            Spacer()
            Text(monthTitle).font(.headline)
            Text("🐶")
            Spacer()
            Picker("", selection: $showYear) {
                Text("月").tag(false)
                Text("年").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: displayedMonth)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(label == "日" ? Color.red.opacity(0.75)
                                     : label == "土" ? Color.blue.opacity(0.75) : Color.secondary)
            }
        }
    }

    /// 月初が何曜日かで決まる先頭の空マス数（日曜始まり）。
    /// 例：2026年12月1日は火曜なので空マス2つで、1日が3列目に来る。
    private var leadingBlanks: Int {
        guard let first = daysInMonth.first else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    private var monthGrid: some View {
        // TODO: 実際の予定データを引いて、予定のある日にアイコン＋場所名を出す
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, minHeight: 44)
            }
            ForEach(daysInMonth, id: \.self) { day in
                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.subheadline)
                        .foregroundStyle(color(for: day))
                    if calendar.isDateInToday(day) {
                        Text("🐾").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { selectedDay = day }
            }
        }
    }

    private var yearGrid: some View {
        // TODO: 12か月ミニカレンダー（予定のある日に小さな肉球マーク）
        Text("年表示（実装中）")
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    private func color(for day: Date) -> Color {
        switch calendar.component(.weekday, from: day) {
        case 1: return .red.opacity(0.75)      // 日曜＝コーラル
        case 7: return .blue.opacity(0.75)     // 土曜＝スカイ
        default: return .primary
        }
    }
}
