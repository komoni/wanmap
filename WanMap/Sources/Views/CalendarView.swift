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

    // MARK: 月表示の連続スクロール（2026-11-14、本人の要望で月跨ぎスクロール化）

    /// スクロール位置（先頭に見えている週の日曜）。初期値は今月1日を含む週で、
    /// ScrollView の初回構築前に決まる（onAppear の scrollTo は使わない）
    @State private var scrollWeekID: Date? = CalendarView.weekSunday(
        containing: CalendarView.firstOfMonth(Date()))
    /// ボタン操作の要求月。シェブロン連打は観測中の月ではなくこの値を基準に加減算する
    @State private var requestedMonth: Date = CalendarView.firstOfMonth(Date())
    /// 実行中のスクロール命令の到達目標週。命令の飛行中は観測で requestedMonth を
    /// 上書きしない（連打の加減算が途中の月でずれるのを防ぐ）
    @State private var commandedWeekID: Date?
    /// 表示ウィンドウ分の週（日曜の日付の列）。今日の月を挟んで -12〜+24 か月分
    @State private var streamWeeks: [Date] = CalendarView.makeStreamWeeks()

    /// 週行の高さ。文字サイズに連動させる（旧・装飾フッター計算の最小高さと同値）
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
                // 月表示は週の連続ストリーム（月跨ぎで上下スクロール）。
                // 曜日見出しだけ固定し、週行がその下を流れる
                VStack(spacing: 6) {
                    weekdayHeader
                    monthStream
                }
            }
        }
        .padding(.horizontal, 12)
        .background(themeStore.canvasColor)
        // ダークテーマではタブバーの未選択項目が暗い地に沈むため、
        // タブバーだけ配色スキームをテーマに合わせる（単位3の撮影検品で発見）
        .toolbarColorScheme(themeStore.appTheme == .dark ? .dark : .light, for: .tabBar)
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
                themeStore.canvasColor
            } else {
                GinghamBand(base: themeStore.cardColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 「今日」ボタンは主ボタン表現（配色案の地色＋白文字）にする。
    /// テーマがパステル以外の時は、配色案ではなくテーマのアクセントを使う
    private var todayButton: some View {
        Button("今日") { setMonth(Date()); showYear = false }
            .buttonStyle(WanPrimaryButtonStyle(
                fill: themeStore.appTheme == .pastel
                    ? appearanceStore.primaryColor : themeStore.accentColor,
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
                Image(systemName: "chevron.left").foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarPrevMonthButton")
            Text(headerTitle)
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(themeStore.dayTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(themeStore.headerIconColor)
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
                Image(systemName: "doc.on.clipboard").foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarStoryImportButton")
            Button { showFriends = true } label: {
                Image(systemName: "person.2").foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarFriendsButton")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(themeStore.headerIconColor)
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
        if showYear {
            // 年表示は表示年を送るだけ（月表示のスクロール位置は観測側に任せる）
            if let next = calendar.date(byAdding: .year, value: value, to: displayedMonth) {
                displayedMonth = next
            }
            return
        }
        // 連打は「最新の要求月」を基準に加減算する（観測中の月で計算すると
        // スクロール途中の月を掴んで行き先がずれる。設計相談 2026-11-14）
        guard let next = calendar.date(byAdding: .month, value: value, to: requestedMonth)
        else { return }
        requestedMonth = clampedToWindow(next)
        commandScroll(toMonth: requestedMonth)
    }

    /// 「今日」ボタン・年表示の月タップからの移動はここを通す。
    /// タイトルは即座に新しい月を示し、月表示のスクロールは対象月の
    /// 1日を含む週へ即時ジャンプする（初版はアニメーションなしの
    /// 即時移動が堅実、という設計相談の結論。2026-11-14）
    private func setMonth(_ date: Date) {
        displayedMonth = date
        requestedMonth = clampedToWindow(Self.firstOfMonth(date))
        commandScroll(toMonth: requestedMonth)
    }

    /// 対象月の1日を含む週へスクロールを命令する
    private func commandScroll(toMonth month: Date) {
        let target = Self.weekSunday(containing: Self.firstOfMonth(month))
        commandedWeekID = target
        scrollWeekID = target
    }

    /// ウィンドウ（streamWeeks の範囲）の外の月は端の月へ寄せる
    private func clampedToWindow(_ month: Date) -> Date {
        guard let first = streamWeeks.first, let last = streamWeeks.last else { return month }
        let startMonth = Self.firstOfMonth(first)
        let endMonth = Self.firstOfMonth(last)
        if month < startMonth { return startMonth }
        if month > endMonth { return endMonth }
        return month
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(label == "日" ? themeStore.accentColor.opacity(0.75)
                                     : label == "土" ? themeStore.saturdayColor.opacity(0.75)
                                     : themeStore.subTextColor)
            }
        }
    }

    /// 月表示の本体：週行の連続ストリーム。月の境目でも日付が途切れず流れ、
    /// 先頭に見えている週からヘッダーの月を決める（判定は month(forWeekSunday:)）。
    /// 旧・月単位グリッド＋装飾フッターは、スクロール化で余白埋めの役目が
    /// 終わったため月表示からは外した（DecorationFooter.swift 自体は残置）
    private var monthStream: some View {
        let grouped = plansByDay
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(streamWeeks, id: \.self) { sunday in
                    weekRow(sunday: sunday, grouped: grouped)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollWeekID, anchor: .top)
        .onChange(of: scrollWeekID) { _, newValue in
            guard let newValue else { return }
            // ヘッダーの月は「その週の土曜が属する月」（＝月初を含む週から
            // 新しい月）。日曜の月で判定すると「8月へ移動したのに7月表示」になる
            let observed = Self.month(forWeekSunday: newValue)
            if !calendar.isDate(observed, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = observed
            }
            if commandedWeekID == newValue {
                // 命令が到達した。要求月を観測月に合わせて確定させる
                commandedWeekID = nil
                requestedMonth = observed
            } else if commandedWeekID == nil {
                // 手動スクロール。次のシェブロンの基準を観測月へ寄せておく
                requestedMonth = observed
            }
        }
    }

    /// 週行（日曜〜土曜の7日）。月跨ぎでも空白マスは作らない
    private func weekRow(sunday: Date, grouped: [Date: [Plan]]) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: sunday) ?? sunday
                dayCell(day, height: minRowHeight,
                        plans: grouped[calendar.startOfDay(for: day)] ?? [])
            }
        }
        .frame(height: minRowHeight)
    }

    private func dayCell(_ day: Date, height: CGFloat, plans dayPlans: [Plan]) -> some View {
        let isToday = calendar.isDateInToday(day)
        return VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle().fill(themeStore.accentColor).frame(width: 24, height: 24)
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
                                .foregroundStyle(themeStore.accentColor)
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
                    .foregroundStyle(themeStore.dayTextColor.opacity(0.75))
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // 高さは週行の高さに固定する（中身は末尾の Spacer と alignment で上寄せを維持）
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
        .background(themeStore.cardColor)
        .clipShape(RoundedRectangle(cornerRadius: WanStyle.cardRadius))
        .overlay(alignment: .topTrailing) {
            // 連続スクロールで月の境目を見失わないための目印（1日のセルだけ月名を出す）
            if calendar.component(.day, from: day) == 1 {
                Text("\(calendar.component(.month, from: day))月")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(themeStore.accentColor)
                    .padding(.top, 4)
                    .padding(.trailing, 5)
                    .accessibilityHidden(true)
            }
        }
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
                .foregroundStyle(themeStore.dayTextColor)
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
        .background(themeStore.cardColor)
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
                    .foregroundStyle(calendar.isDateInToday(day) ? themeStore.accentColor : color(for: day))
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
        case 1: return themeStore.accentColor.opacity(0.75)    // 日曜＝アクセント
        case 7: return themeStore.saturdayColor.opacity(0.75)  // 土曜＝テーマの土曜色
        default: return themeStore.dayTextColor                // 本文＝テーマの本文色
        }
    }

    // MARK: - 週ストリームの日付ユーティリティ（静的。@State の初期値からも使う）

    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = 1  // インスタンス側 calendar と同じ日曜始まり固定
        return c
    }()

    /// 月の1日（startOfDay）
    private static func firstOfMonth(_ date: Date) -> Date {
        gregorian.date(from: gregorian.dateComponents([.year, .month], from: date)) ?? date
    }

    /// その日を含む週の日曜（startOfDay）
    private static func weekSunday(containing date: Date) -> Date {
        let start = gregorian.startOfDay(for: date)
        let weekday = gregorian.component(.weekday, from: start)
        return gregorian.date(byAdding: .day, value: -(weekday - 1), to: start) ?? start
    }

    /// 週（日曜）の属する月＝その週の土曜の月（月初を含む週から新しい月として扱う）
    private static func month(forWeekSunday sunday: Date) -> Date {
        let saturday = gregorian.date(byAdding: .day, value: 6, to: sunday) ?? sunday
        return firstOfMonth(saturday)
    }

    /// 今日の月を挟んで -12〜+24 か月分の週（日曜の列）
    private static func makeStreamWeeks() -> [Date] {
        let anchor = firstOfMonth(Date())
        guard let startMonth = gregorian.date(byAdding: .month, value: -12, to: anchor),
              let endMonth = gregorian.date(byAdding: .month, value: 24, to: anchor),
              let nextAfterEnd = gregorian.date(byAdding: .month, value: 1, to: endMonth),
              let endLastDay = gregorian.date(byAdding: .day, value: -1, to: nextAfterEnd)
        else { return [weekSunday(containing: anchor)] }
        var weeks: [Date] = []
        var cursor = weekSunday(containing: startMonth)
        let last = weekSunday(containing: endLastDay)
        while cursor <= last {
            weeks.append(cursor)
            guard let next = gregorian.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
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
