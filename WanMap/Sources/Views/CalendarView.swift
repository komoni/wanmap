import SwiftUI

/// 犬専用カレンダー（メイン画面）
/// 仕様：柔らかいパステル、日曜コーラル／土曜スカイ、今日はアクセント丸＋小さな肉球。
/// 各日はアイコン＋場所名だけ（件数や空状態メッセージは出さない）。月／年 切り替えあり。
/// 予定は PlanStore の実データを表示し、日タップでその日の予定一覧シートを開く。
struct CalendarView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ThemeStore.self) private var themeStore

    @State private var displayedMonth: Date = Date()
    @State private var showYear = false
    @State private var daySelection: DaySelection?
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var showStoryImport = false

    private struct DaySelection: Identifiable {
        let id = UUID()
        let day: Date
    }

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = 1  // 日曜始まりで固定（端末設定でズレないように）
        return c
    }()

    /// 日（startOfDay）→ その日の予定。月表示・年表示の両方で使う
    private var plansByDay: [Date: [Plan]] {
        Dictionary(grouping: planStore.activePlans) { calendar.startOfDay(for: $0.date) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // 広告／イベント告知バナー（地図画面と共通の枠。フロー内・固定高で操作の邪魔にならない）
            InfoBannerView(items: InfoBannerView.items(upcomingEvents: planStore.upcomingEvents()))
            header
            if showYear {
                yearGrid
            } else {
                // 月グリッドが残りの高さいっぱいに広がる（下の空白を作らない）
                VStack(spacing: 6) {
                    weekdayHeader
                    monthGrid
                }
            }
        }
        .padding(.horizontal, 12)
        .background(WanStyle.canvas)
        .sheet(item: $daySelection) { selection in
            DayPlansView(day: selection.day)
        }
        .sheet(isPresented: $showFriends) { FriendsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showStoryImport) { StoryImportView() }
    }

    private var header: some View {
        // 要素数が多く合計幅が画面幅を超えやすい。タイトルは圧縮抵抗が低く
        // 真っ先に潰れて折り返すため、1行固定＋レイアウト優先度を上げ、
        // ピッカー幅と間隔を詰めてタイトル分の幅を確保する。
        HStack(spacing: 6) {
            Button("今日") { displayedMonth = Date(); showYear = false }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Text("🐶")
            Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
            Spacer()
            Picker("", selection: $showYear) {
                Text("月").tag(false)
                Text("年").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 84)
            HStack(spacing: 8) {
                Button { showStoryImport = true } label: { Image(systemName: "doc.on.clipboard") }
                Button { showFriends = true } label: { Image(systemName: "person.2") }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
                    .accessibilityIdentifier("calendarSettingsButton")
            }
        }
    }

    private var headerTitle: String {
        if showYear {
            return "\(calendar.component(.year, from: displayedMonth))年"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: displayedMonth)
    }

    private func shift(by value: Int) {
        let component: Calendar.Component = showYear ? .year : .month
        if let next = calendar.date(byAdding: component, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(label == "日" ? WanStyle.coral.opacity(0.75)
                                     : label == "土" ? WanStyle.saturday.opacity(0.75) : Color.secondary)
            }
        }
    }

    /// 月グリッド。週の行（HStack）を縦に積み、各行・各セルが利用可能な
    /// 高さいっぱいに均等に広がる形にする（LazyVGrid は行の高さを余らせて
    /// 下に空白ができるため使わない）。空マスは weeksIn が nil で埋める。
    /// セルの中身は上寄せのまま、セル自体の高さだけが伸びる。
    private var monthGrid: some View {
        let weeks = weeksIn(displayedMonth)
        return VStack(spacing: 6) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 6) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let day = weeks[weekIndex][dayIndex] {
                            dayCell(day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func dayCell(_ day: Date) -> some View {
        let dayPlans = plansByDay[calendar.startOfDay(for: day)] ?? []
        let isToday = calendar.isDateInToday(day)
        return VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle().fill(WanStyle.coral).frame(width: 24, height: 24)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline)
                    .foregroundStyle(isToday ? Color.white : color(for: day))
            }
            if isToday {
                Text("🐾").font(.system(size: 8))
            }
            // アイコン＋場所名だけ（最大2件）。未登録地点の「今ここ」は人アイコンのみで場所名なし
            // フェーズN：予定行はカプセル＋ココア文字のチップ表現にする
            // フェーズO：チップの地色は設定で選べる ThemeStore の値（デフォルトはラベンダー）
            ForEach(dayPlans.prefix(2)) { plan in
                HStack(spacing: 2) {
                    ZStack {
                        Circle().fill(WanStyle.card).frame(width: 12, height: 12)
                        if plan.isPresence {
                            Image(systemName: "person.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(WanStyle.coral)
                        } else {
                            Text("🐶").font(.system(size: 8))
                        }
                    }
                    if !plan.placeName.isEmpty {
                        Text(plan.placeName)
                            .font(.caption2)
                            .foregroundStyle(WanStyle.cocoa)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(themeStore.chipColor, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // 高さは週の行いっぱいに伸ばす（中身は末尾の Spacer と alignment で上寄せを維持）
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity, alignment: .top)
        .background(WanStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { daySelection = DaySelection(day: day) }
    }

    // MARK: - 年表示（12か月のミニカレンダー。予定のある日に印。タップでその月の月表示へ）

    private var yearGrid: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(1..<4, id: \.self) { col in
                            miniMonth(month: row * 3 + col)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func miniMonth(month: Int) -> some View {
        let year = calendar.component(.year, from: displayedMonth)
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? displayedMonth
        let weeks = weeksIn(first)
        return VStack(spacing: 2) {
            Text("\(month)月")
                .font(.caption)
                .bold()
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 1) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        miniDayCell(weeks[weekIndex][dayIndex])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(WanStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            displayedMonth = first
            showYear = false
        }
    }

    private func miniDayCell(_ day: Date?) -> some View {
        ZStack {
            if let day {
                if let plans = plansByDay[calendar.startOfDay(for: day)], !plans.isEmpty {
                    Circle().fill(WanStyle.lavender)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 8))
                    .foregroundStyle(calendar.isDateInToday(day) ? WanStyle.coral : color(for: day))
                    .bold(calendar.isDateInToday(day))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 13)
    }

    /// 月を週ごとのマス（空マスは nil）に並べる
    private func weeksIn(_ month: Date) -> [[Date?]] {
        let days = daysIn(month)
        guard let first = days.first else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    // MARK: - 日付ユーティリティ

    private func daysIn(_ month: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    private func color(for day: Date) -> Color {
        switch calendar.component(.weekday, from: day) {
        case 1: return WanStyle.coral.opacity(0.75)      // 日曜＝コーラル
        case 7: return WanStyle.saturday.opacity(0.75)   // 土曜＝ソフトブルー
        default: return WanStyle.cocoa                   // 本文＝ココア
        }
    }
}

#if DEBUG
#Preview {
    CalendarView()
        .environment(FacilityStore())
        .environment(PlanStore(samplePlans: SeedData.samplePlans()))
        .environment(ThemeStore())
}
#endif
