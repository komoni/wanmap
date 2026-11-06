import SwiftUI

/// 犬専用カレンダー（メイン画面）
/// 仕様：柔らかいパステル、日曜コーラル／土曜スカイ、今日はアクセント丸＋小さな肉球。
/// 各日はアイコン＋場所名だけ（件数や空状態メッセージは出さない）。月／年 切り替えあり。
/// 予定は PlanStore の実データを表示し、日タップでその日の予定一覧シートを開く。
struct CalendarView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(AppearanceStore.self) private var appearanceStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        // ヘッダーの帯だけに淡いギンガムを敷く（他の画面・セルには広げない）。
        // 「透明度を下げる」設定時は柄を消して無地（ミルク）にする。
        // レイアウトは AppearanceStore の比較案で切り替わる：
        // 1段（現行）／2段（補助操作を下段へ）。既定は1段。
        //
        // 幅の予算（iPhone 16 Pro＝402pt、画面の横余白12を引いた帯の内寸は
        // 1段＝370pt／2段＝358pt）：全要素を並べると簡単に溢れ、圧縮抵抗の低い
        // タイトルとハスキー顔から潰れて消える（CI #49で確認）。
        // そのためタイトルとハスキーは fixedSize＋layoutPriority で保護し、
        // 幅の調整はヘッダー内に限る（タップ枠は高さ44pt維持で幅だけ詰める、
        // Picker幅、帯の内側余白、今日ボタンの内側余白）。
        // 1段の内訳目安：今日約45＋クラスタ約167＋Picker 56＋補助約94＝約362pt。
        Group {
            if appearanceStore.headerLayout == .stacked {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        todayButton
                        Spacer(minLength: 0)
                        monthNavCluster(compact: false)
                        Spacer(minLength: 0)
                        monthYearPicker(width: 84)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        auxButtons(compact: false)
                    }
                }
                .padding(.horizontal, 10)
            } else {
                HStack(spacing: 0) {
                    todayButton
                    Spacer(minLength: 0)
                    monthNavCluster(compact: true)
                    Spacer(minLength: 0)
                    monthYearPicker(width: 56)
                    auxButtons(compact: true)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 4)
        .background {
            if reduceTransparency {
                WanStyle.canvas
            } else {
                GinghamBand()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 「今日」ボタンは主ボタン表現（配色案の地色＋白文字）にする
    private var todayButton: some View {
        Button("今日") { displayedMonth = Date(); showYear = false }
            .buttonStyle(WanPrimaryButtonStyle(fill: appearanceStore.primaryColor,
                                               horizontalPadding: 8, verticalPadding: 6))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 年月タイトル＋前後月＋ハスキー顔（旧🐶絵文字の置換。静止画・装飾扱い）
    /// compact＝1段用（タップ枠の幅・タイトル・ハスキーを詰める）。
    /// タイトルとハスキーは fixedSize＋layoutPriority で圧縮から守る
    /// （潰れるくらいなら周りの余白が先に詰まるようにする）。
    private func monthNavCluster(compact: Bool) -> some View {
        HStack(spacing: 2) {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(WanStyle.coral)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarPrevMonthButton")
            Text(headerTitle)
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Image("HuskyFace")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                .fixedSize()
                .layoutPriority(2)
                .accessibilityHidden(true)
            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(WanStyle.coral)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarNextMonthButton")
        }
    }

    private func monthYearPicker(width: CGFloat) -> some View {
        Picker("", selection: $showYear) {
            Text("月").tag(false)
            Text("年").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 補助操作（取り込み・友達・設定）。タップ領域の高さは44ptを維持し、
    /// 1段（compact）では幅だけ30ptに詰める
    private func auxButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 2 : 8) {
            Button { showStoryImport = true } label: {
                Image(systemName: "doc.on.clipboard").foregroundStyle(WanStyle.coral)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarStoryImportButton")
            Button { showFriends = true } label: {
                Image(systemName: "person.2").foregroundStyle(WanStyle.coral)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarFriendsButton")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(WanStyle.coral)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarSettingsButton")
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
        // UIテストが日セル自体を一意に掴むための識別子（見た目・挙動・読み上げは不変）。
        // セル内の数字テキストは中身やOSの表現に左右され、ラベル検索が安定しないため
        .accessibilityIdentifier(dayCellIdentifier(day))
    }

    /// 日セルの識別子（例：calendarDayCell-2026-12-06）。月表示の日ごとに一意
    private func dayCellIdentifier(_ day: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "calendarDayCell-%04d-%02d-%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0)
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

/// ヘッダー専用のタップ領域。共通の wanTapTarget（44×44pt）は地図画面でも
/// 使うため変えず、ヘッダーでは compact 時に幅だけ30ptへ詰める（高さ44ptは維持）。
private struct HeaderTapTarget: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content
                .frame(minWidth: 30, minHeight: 44)
                .contentShape(Rectangle())
        } else {
            content.wanTapTarget()
        }
    }
}

#if DEBUG
#Preview {
    CalendarView()
        .environment(FacilityStore())
        .environment(PlanStore(samplePlans: SeedData.samplePlans()))
        .environment(ThemeStore())
        .environment(AppearanceStore())
}
#endif
