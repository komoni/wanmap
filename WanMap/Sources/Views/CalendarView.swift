import SwiftUI

/// 犬専用カレンダー（メイン画面）
/// 仕様：柔らかいパステル、日曜コーラル／土曜スカイ、今日はアクセント丸＋小さな肉球。
/// 各日はアイコン＋場所名だけ（件数や空状態メッセージは出さない。ただし
/// セルに収まらず隠れた予定の残件数「＋N件」だけは出す＝情報の欠落を伝える）。月／年 切り替えあり。
/// 予定は PlanStore の実データを表示し、日タップでその日の予定一覧シートを開く。
struct CalendarView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(AppearanceStore.self) private var appearanceStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedMonth: Date = Date()
    @State private var showYear = false
    @State private var daySelection: DaySelection?
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var showStoryImport = false

    /// セルの最小高さ（デザイン第二弾の装飾フッター計算用）。文字サイズに連動させる
    @ScaledMetric(relativeTo: .subheadline) private var minRowHeight: CGFloat = 76

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

    /// ※ヘッダーのハスキー顔は 2026-11-07 に本人の指示で表示を取りやめた
    /// （月タイトル横の装飾は不要との判断）。画像ファイル自体は将来の再利用に
    /// 備えてバンドルに残してある（同梱の回帰ガードは HuskyFaceResourceTests）。

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
                // 月グリッド＋装飾フッターが残りの高さいっぱいに広がる。
                // 実測した高さからセルの最小高さを確保し、余りだけ装飾に回す
                // （MonthDecorationLayout。装飾でセルを潰さない）
                VStack(spacing: 6) {
                    weekdayHeader
                    GeometryReader { geo in
                        monthArea(availableHeight: geo.size.height)
                    }
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
        // 1段／2段（補助操作を下段へ）。既定は2段＋コーラル（2026-11-07に本人が選択）。
        //
        // 幅の予算（iPhone 16 Pro＝402pt、画面の横余白12を引いた帯の内寸は
        // 1段＝370pt／2段＝358pt）：全要素を並べると簡単に溢れ、圧縮抵抗の低い
        // タイトルから潰れて消える（CI #49で確認。顔画像は後に本人の指示で撤去）。
        // そのためタイトルは fixedSize＋layoutPriority で保護し、
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
        Button("今日") { setMonth(Date()); showYear = false }
            .buttonStyle(WanPrimaryButtonStyle(fill: appearanceStore.primaryColor,
                                               horizontalPadding: 8, verticalPadding: 6))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 年月タイトル＋前後月。
    /// compact＝1段用（タップ枠の幅・タイトルを詰める）。
    /// タイトルは fixedSize＋layoutPriority で圧縮から守る
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
            setMonth(next)
        }
    }

    /// 月（年）の切り替えはここを通す。グリッドだけが短くクロスフェードし、
    /// タイトルは即座に新しい月を示す（monthArea 側の .id/.transition と対）。
    /// 連打時は最新へ追従する（途中を順番に再生しない）。Reduce Motion 時は
    /// アニメーションなしの即時切替（第2単位2-B、2026-11-12）
    private func setMonth(_ date: Date) {
        if reduceMotion {
            displayedMonth = date
        } else {
            withAnimation(.easeOut(duration: 0.18)) { displayedMonth = date }
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

    /// グリッド＋装飾フッター。実測の高さからレイアウトを決める
    private func monthArea(availableHeight: CGFloat) -> some View {
        let weeks = weeksIn(displayedMonth)
        let layout = MonthDecorationLayout.compute(
            availableHeight: availableHeight,
            weeks: weeks.count,
            rowSpacing: 6,
            footerSpacing: 6,
            minRowHeight: minRowHeight)
        return VStack(spacing: 6) {
            monthGrid(weeks: weeks, rowHeight: layout.rowHeight)
                // 月が変わったらグリッドだけをクロスフェードさせる
                // （見出し・曜日・枠は安定。フェード時間は setMonth 側と対）
                .id(monthTransitionKey)
                .transition(.opacity)
            if layout.footerHeight > 0 {
                DecorationFooterView(stage: layout.stage, height: layout.footerHeight)
            }
        }
    }

    /// クロスフェードの対象を月ごとに切り替えるためのキー
    private var monthTransitionKey: String {
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        return "\(year)-\(month)-\(showYear)"
    }

    /// 月グリッド。週の行（HStack）を縦に積み、各行の高さは
    /// MonthDecorationLayout が決めた rowHeight で均等にする
    /// （LazyVGrid は行の高さを余らせて下に空白ができるため使わない）。
    /// 空マスは weeksIn が nil で埋める。セルの中身は上寄せのまま。
    private func monthGrid(weeks: [[Date?]], rowHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 6) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let day = weeks[weekIndex][dayIndex] {
                            dayCell(day, height: rowHeight)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func dayCell(_ day: Date, height: CGFloat) -> some View {
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
            // 3件目以降はセルに収まらない。隠れていること自体を伝える
            // （第2単位の追加点、2026-11-12。情報の欠落は演出より先に直す）
            if dayPlans.count > 2 {
                Text("＋\(dayPlans.count - 2)件")
                    .font(.caption2)
                    .foregroundStyle(WanStyle.cocoa.opacity(0.75))
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // 高さは MonthDecorationLayout の行高に固定する（中身は末尾の Spacer と alignment で上寄せを維持）
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
        .background(WanStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: WanStyle.cardRadius))
        .onTapGesture { daySelection = DaySelection(day: day) }
        // UIテストが日セル自体を一意に掴むための識別子。
        // セル内の数字テキストは中身やOSの表現に左右され、ラベル検索が安定しないため
        .accessibilityIdentifier(dayCellIdentifier(day))
        // 読み上げは日付・今日・予定の内訳を1つにまとめる。セルは
        // onTapGesture なのでボタン特性も付ける（第2単位スポット確認、2026-11-12）
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dayCellAccessibilityLabel(day: day, plans: dayPlans))
        .accessibilityHint("予定一覧が開きます")
        .accessibilityAddTraits(.isButton)
    }

    /// 日セルの読み上げラベル（例：「11月15日（土）、予定3件：ドッグウィズ、sea、ほか1件」）
    private func dayCellAccessibilityLabel(day: Date, plans: [Plan]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        var label = f.string(from: day)
        if calendar.isDateInToday(day) { label += "、今日" }
        if plans.isEmpty {
            label += "、予定なし"
        } else {
            let names = plans.prefix(2).map { plan in
                plan.isPresence ? "今ここ" : (plan.placeName.isEmpty ? "場所未定" : plan.placeName)
            }
            label += "、予定\(plans.count)件：" + names.joined(separator: "、")
            if plans.count > 2 { label += "、ほか\(plans.count - 2)件" }
        }
        return label
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
        .clipShape(RoundedRectangle(cornerRadius: WanStyle.cardRadius))
        .onTapGesture {
            setMonth(first)
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
