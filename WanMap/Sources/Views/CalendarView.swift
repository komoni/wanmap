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
    @State private var showEvents = false
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var showStoryImport = false

    // MARK: 月表示（月ブロックの縦スクロール、iPhone純正カレンダー方式）
    //
    // 経緯：2026-11-14 に週の連続ストリーム（月跨ぎで日付が一続きに流れる形）を
    // 入れたが、本人の実機所感で「全ての日付が並んだ状態は違う。月表示は
    // 月表示のまま、上下スライドで前月・次月へ移動する純正カレンダーと同じ形に」
    // と差し替え指示があり、月ブロック方式へ作り替えた（同日）。

    /// スクロール位置（先頭に見えている月の1日）。初期値は今月の1日で、
    /// ScrollView の初回構築前に決まる（onAppear の scrollTo は使わない）
    @State private var scrollMonthID: Date? = CalendarView.firstOfMonth(Date())
    /// ボタン操作の要求月。シェブロン連打は観測中の月ではなくこの値を基準に加減算する
    @State private var requestedMonth: Date = CalendarView.firstOfMonth(Date())
    /// 実行中のスクロール命令の到達目標月。命令の飛行中は観測で requestedMonth を
    /// 上書きしない（連打の加減算が途中の月でずれるのを防ぐ）
    @State private var commandedMonthID: Date?
    /// 表示ウィンドウ分の月（各月の1日の列）。今日の月を挟んで -12〜+24 か月分
    @State private var streamMonths: [Date] = CalendarView.makeStreamMonths()

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
                // 月表示は月ごとのブロック（月表示の形は維持し、上下スライドで
                // 前月・次月へ移動する。iPhone純正カレンダーと同じ考え方）。
                // 曜日見出しだけ固定し、月ブロックがその下を流れる。
                // 1ブロック分の高さを超えた余白には装飾フッター（恐竜ハスキー＋
                // 波帯）を出す。旧・月グリッド時代の設計の月ブロックへの移植で、
                // 週ストリーム時代に外れていたフッターの復活（2026-11-14）
                VStack(spacing: 6) {
                    weekdayHeader
                    GeometryReader { geo in
                        // フッターはスクロールの下端に重ねて出す。レイアウト内の
                        // 配置だと、ヘッダー拡大後の画面高では余白が足りず犬まで
                        // 出せない（CIスクショで波だけになるのを確認、2026-11-14）。
                        // 重ね分（56pt）を余白に足して判定し、最後の月ブロックが
                        // フッターに隠れずスクロールし切れるよう、スクロール側に
                        // 下マージンも持たせる
                        let layout = MonthDecorationLayout.compute(
                            availableHeight: geo.size.height - 26 + 56,
                            weeks: 6, rowSpacing: 6, footerSpacing: 6,
                            minRowHeight: minRowHeight)
                        ZStack(alignment: .bottom) {
                            monthBlocks
                            if layout.footerHeight > 0 {
                                DecorationFooterView(stage: layout.stage,
                                                     height: layout.footerHeight)
                            }
                        }
                    }
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
        .sheet(isPresented: $showEvents) { EventsView() }
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
        // 年月表示と前後マークは本人の指示で従来の1.5倍サイズ（2026-11-14）
        HStack(spacing: 2) {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: compact ? 23 : 26))
                    .foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarPrevMonthButton")
            Text(headerTitle)
                .font(.system(size: compact ? 23 : 26, weight: .semibold))
                .foregroundStyle(themeStore.dayTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: compact ? 23 : 26))
                    .foregroundStyle(themeStore.headerIconColor)
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

    /// 補助操作（イベント・取り込み・友達・設定）。タップ領域の高さは44ptを維持し、
    /// 1段（compact）では幅だけ30ptに詰める。
    /// イベントは旧タブの統合先（実機フィードバック⑩、2026-11-14）
    private func auxButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 2 : 8) {
            Button { showEvents = true } label: {
                Image(systemName: "ticket")
                    .font(.system(size: 25))
                    .foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarEventsButton")
            Button { showStoryImport = true } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 25))
                    .foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
            .accessibilityIdentifier("calendarStoryImportButton")
            Button { showFriends = true } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 25))
                    .foregroundStyle(themeStore.headerIconColor)
            }
            .buttonStyle(WanPressButtonStyle())
            .modifier(HeaderTapTarget(compact: compact))
            .accessibilityIdentifier("calendarFriendsButton")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 25))
                    .foregroundStyle(themeStore.headerIconColor)
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
    /// ブロックへ即時ジャンプする
    private func setMonth(_ date: Date) {
        displayedMonth = date
        requestedMonth = clampedToWindow(Self.firstOfMonth(date))
        commandScroll(toMonth: requestedMonth)
    }

    /// 対象月のブロックへスクロールを命令する
    private func commandScroll(toMonth month: Date) {
        let target = Self.firstOfMonth(month)
        commandedMonthID = target
        scrollMonthID = target
    }

    /// ウィンドウ（streamMonths の範囲）の外の月は端の月へ寄せる
    private func clampedToWindow(_ month: Date) -> Date {
        guard let first = streamMonths.first, let last = streamMonths.last else { return month }
        if month < first { return first }
        if month > last { return last }
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

    /// 月表示の本体：月ブロックの縦スクロール。上下スライドで月ブロック単位に
    /// 吸着して前月・次月へ移動する（viewAligned）。先頭に見えているブロックの
    /// 月がヘッダーの月になる
    private var monthBlocks: some View {
        let grouped = plansByDay
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(streamMonths, id: \.self) { month in
                    monthSection(month, grouped: grouped)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollMonthID, anchor: .top)
        // 下端に重なる装飾フッターの分だけ余白を持ち、最後のブロックも
        // フッターの上までスクロールし切れるようにする
        .contentMargins(.bottom, 110, for: .scrollContent)
        .onChange(of: scrollMonthID) { _, newValue in
            guard let newValue else { return }
            let observed = Self.firstOfMonth(newValue)
            if !calendar.isDate(observed, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = observed
            }
            if commandedMonthID == observed {
                // 命令が到達した。要求月を観測月に合わせて確定させる
                commandedMonthID = nil
                requestedMonth = observed
            } else if commandedMonthID == nil {
                // 手動スクロール。次のシェブロンの基準を観測月へ寄せておく
                requestedMonth = observed
            }
        }
    }

    /// 月ブロック：月名の見出し＋その月だけの週グリッド。月外の日は空白マスに
    /// して週を月と月で共有しない（純正カレンダーと同じ。週ストリーム版への
    /// 本人の差し替え指示、2026-11-14）。
    /// 全ブロックを必ず6週分の高さに揃える（5週の月は空白週を足す）。
    /// LazyVStack は未表示セクションの高さを推定してジャンプ先を計算するため、
    /// 高さが月ごとに違うと推定誤差で初期表示・長距離ジャンプが手前の月に
    /// ズレて着地する（CI run 43563554435 で初期表示が2か月ズレ＋UIテスト
    /// 5件失敗として実発生）。高さ均一化がその対策
    private func monthSection(_ month: Date, grouped: [Date: [Plan]]) -> some View {
        let weeks = weeksIn(month)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(calendar.component(.month, from: month))月")
                .font(.headline)
                .foregroundStyle(themeStore.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { weekIndex in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            if weekIndex < weeks.count, let day = weeks[weekIndex][dayIndex] {
                                dayCell(day, height: minRowHeight,
                                        plans: grouped[calendar.startOfDay(for: day)] ?? [])
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: minRowHeight)
                            }
                        }
                    }
                    .frame(height: minRowHeight)
                }
            }
        }
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
        if let holiday = HolidayCalendar.name(for: day) { label += "、祝日：\(holiday)" }
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
        // 祝日は曜日に関わらず日曜と同じアクセント色にする（2026-11-14、祝日表示の追加）
        if HolidayCalendar.isHoliday(day) {
            return themeStore.accentColor.opacity(0.75)
        }
        switch calendar.component(.weekday, from: day) {
        case 1: return themeStore.accentColor.opacity(0.75)    // 日曜＝アクセント
        case 7: return themeStore.saturdayColor.opacity(0.75)  // 土曜＝テーマの土曜色
        default: return themeStore.dayTextColor                // 本文＝テーマの本文色
        }
    }

    // MARK: - 月ブロックの日付ユーティリティ（静的。@State の初期値からも使う）

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

    /// 今日の月を挟んで -12〜+24 か月分の月（各月の1日の列）
    private static func makeStreamMonths() -> [Date] {
        let anchor = firstOfMonth(Date())
        var months: [Date] = []
        for offset in -12...24 {
            if let month = gregorian.date(byAdding: .month, value: offset, to: anchor) {
                months.append(month)
            }
        }
        return months.isEmpty ? [anchor] : months
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
