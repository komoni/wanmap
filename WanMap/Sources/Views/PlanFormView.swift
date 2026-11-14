import SwiftUI

/// 予定の追加・編集フォーム（共通シート）
///
/// 仕様（決定済み）：
/// - 場所は登録済み施設からの候補検索で選ぶか、住所テキストとして直接入力する（緯度経度の数値入力はしない）
/// - 自分で追加した場所（UserPlace）も候補に出し、公式施設より優先して先に並べる。選ぶと座標付きの予定になる
/// - 場所のエリア（地域）入力欄は作らない
/// - 「自分の位置を見せない」トグルはこのフォーム内にだけ置く（カレンダー／地図のバーには置かない）
/// - 犬の名前の初期値：プロフィール（自分の犬）の名前があればそれを優先し、
///   無ければ前回使った名前（PlanStore.lastDogName）にする
struct PlanFormView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(FriendStore.self) private var friendStore
    @Environment(FacilityStore.self) private var facilityStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(AppearanceStore.self) private var appearanceStore
    @Environment(FeedbackService.self) private var feedback
    @Environment(\.dismiss) private var dismiss

    let editing: Plan?

    @State private var date: Date
    @State private var timeBand: TimeBand
    @State private var level: AttendanceLevel
    @State private var dogName: String
    @State private var isEvent: Bool
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hidesOwnLocation: Bool
    @State private var placeQuery: String
    @State private var selectedFacility: Facility?
    @State private var selectedUserPlace: UserPlace?
    /// 繰り返しの種類（新規作成時のみ。nil＝繰り返しなし）
    @State private var recurrenceKind: RecurrenceKind?
    /// 繰り返しの回数（初回を含む。3／6／12）
    @State private var occurrenceCount: Int = 3
    /// シリーズの子を編集中の対象範囲（この回だけ／シリーズ全体）
    @State private var editScope: PlanEditScope = .occurrence
    /// 削除範囲ダイアログの対象（シリーズの子を削除する時だけ使う）
    @State private var deletionTarget: Plan?
    /// 削除範囲ダイアログの表示状態（対象とは分離して管理する。F1）
    @State private var showDeletionDialog = false
    /// 保存に失敗した時の表示（失敗したらフォームは閉じず、入力を保持する。R3）
    @State private var saveErrorMessage: String?
    /// シリーズ全体編集の基準にする、保存済み場所（親の共通内容）の控え（R5）
    @State private var seriesPlaceSnapshot: SavedPlace?

    /// 保存済みの場所の控え。編集の基準は常にこの控えとし、名前の照合だけで
    /// 別の登録場所の座標に暗黙に差し替わることはない（R5）。
    private struct SavedPlace {
        var name: String
        var latitude: Double?
        var longitude: Double?
    }

    /// initialFacility：施設シートから開く時にその施設（名前・座標）を選択済みにする
    /// initialUserPlace：自分の場所のシートから開く時にその場所を選択済みにする
    /// initialTimeBand：推測ドラフトなど、時間帯を決め打ちで開きたい時に使う
    init(editing: Plan?, defaultDate: Date = Date(), defaultDogName: String = "",
         initialTimeBand: TimeBand? = nil,
         initialFacility: Facility? = nil, initialUserPlace: UserPlace? = nil) {
        self.editing = editing
        _date = State(initialValue: editing?.date ?? defaultDate)
        _timeBand = State(initialValue: editing?.timeBand ?? initialTimeBand ?? .allDay)
        _level = State(initialValue: editing?.level ?? .going)
        _dogName = State(initialValue: editing?.dogName ?? defaultDogName)
        _isEvent = State(initialValue: editing?.isEvent ?? false)
        _hasDeadline = State(initialValue: editing?.eventDeadline != nil)
        _deadline = State(initialValue: editing?.eventDeadline ?? (editing?.date ?? defaultDate))
        _hidesOwnLocation = State(initialValue: editing?.hidesOwnLocation ?? false)
        _placeQuery = State(initialValue: editing?.placeName
            ?? initialFacility?.displayName ?? initialUserPlace?.name ?? "")
        _selectedFacility = State(initialValue: initialFacility)
        _selectedUserPlace = State(initialValue: initialUserPlace)
    }

    /// 何か選択済みの間は候補を出さない
    private var hasSelection: Bool { selectedFacility != nil || selectedUserPlace != nil }

    /// 自分で追加した場所の候補（公式施設より優先して先に出す）
    private var userPlaceCandidates: [UserPlace] {
        guard !hasSelection else { return [] }
        return Array(userPlaceStore.search(placeQuery).prefix(4))
    }

    private var candidates: [Facility] {
        guard !hasSelection else { return [] }
        return Array(facilityStore.search(placeQuery).prefix(8))
    }

    /// 編集対象が属するシリーズ（通常予定・新規作成では nil）
    private var editingSeries: RecurrenceSeries? {
        guard let editing else { return nil }
        return planStore.seriesFor(editing)
    }

    /// 保存失敗アラートの表示制御（メッセージが入っている間だけ出す）
    private var saveErrorPresented: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                if planStore.loadFailed {
                    Section {
                        Label("保存データを読み込めなかったため、変更は保存されません。設定からデータをリセットすると、空の状態から始められます。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                placeSection
                if editingSeries != nil { scopeSection }
                dateSection
                if editing == nil { recurrenceSection }
                dogSection
                typeSection
                privacySection
                if editing != nil { deleteSection }
            }
            .navigationTitle(editing == nil ? "予定を追加" : "予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                        .tint(appearanceStore.primaryColor)
                }
            }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .onAppear(perform: resolvePlaceFromEditingPlan)
            .onAppear {
                // 新規作成の初期値：プロフィール（自分の犬）の名前が登録済みなら
                // それを犬の名前欄へ反映する（実機フィードバック⑪、2026-11-14）。
                // 編集時は予定自身の名前が初期値なので触らない
                if editing == nil, let profileDogName = friendStore.me.dogName,
                   !profileDogName.isEmpty {
                    dogName = profileDogName
                }
            }
            .onChange(of: placeQuery) { _, newValue in
                // 手で書き換えたら選択は解除する（そのまま住所テキストとして扱う）
                if let facility = selectedFacility, newValue != facility.displayName {
                    selectedFacility = nil
                }
                if let place = selectedUserPlace, newValue != place.name {
                    selectedUserPlace = nil
                }
            }
        }
        // 削除範囲ダイアログは Form の内側ではなく、NavigationStack
        // （安定したホスト）に付ける（F1）
        .seriesDeletionDialog(target: $deletionTarget, isPresented: $showDeletionDialog,
                              store: planStore,
                              onDeleted: { dismiss() },
                              onFailure: { presentSaveError("削除を保存できませんでした。") })
    }

    private var placeSection: some View {
        Section {
            TextField("場所を検索", text: $placeQuery)
                .textInputAutocapitalization(.never)
            if let facility = selectedFacility {
                HStack {
                    Label(facility.displayName, systemImage: "mappin.circle.fill")
                        .foregroundStyle(WanStyle.coral)
                    Spacer()
                    Button {
                        selectedFacility = nil
                        placeQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else if let place = selectedUserPlace {
                HStack {
                    Label(place.name, systemImage: "mappin.circle.fill")
                        .foregroundStyle(WanStyle.coral)
                    Spacer()
                    Button {
                        selectedUserPlace = nil
                        placeQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(userPlaceCandidates) { place in
                    Button {
                        selectedUserPlace = place
                        placeQuery = place.name
                    } label: {
                        HStack {
                            Text(place.kind.markerEmoji)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name).foregroundStyle(.primary)
                                Text("自分で登録した場所")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(candidates) { facility in
                    Button {
                        selectedFacility = facility
                        placeQuery = facility.displayName
                    } label: {
                        HStack {
                            Image(systemName: "pawprint.fill").foregroundStyle(WanStyle.coral)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(facility.displayName).foregroundStyle(.primary)
                                if let address = facility.address {
                                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Label("場所", systemImage: "mappin.and.ellipse")
        } footer: {
            Text("施設が見つからなければ、住所をそのまま入力しても大丈夫です")
        }
    }

    /// シリーズの子の編集で、対象範囲を選ぶ（この回だけ／この回以降／シリーズ全体）。
    /// 切り替えると入力欄は、選んだ範囲の内容（この回／シリーズの共通内容）で読み直される。
    /// 「全体」と「以降」では例外回の扱いが違う（全体＝上書き、以降＝保護）ため、
    /// その違いを各スコープの説明文で利用者に伝える（単位4の決定事項）。
    private var scopeSection: some View {
        Section {
            Picker("", selection: $editScope) {
                Text("この回だけ").tag(PlanEditScope.occurrence)
                Text("この回以降").tag(PlanEditScope.following)
                Text("シリーズ全体").tag(PlanEditScope.series)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: editScope) { _, scope in applyScope(scope) }
            if editScope == .series, let series = editingSeries {
                Text("残っている\(planStore.occurrences(of: series.id).count)件すべてに、変更した項目だけが反映されます。個別に変更した同じ項目も上書きされます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if editScope == .following, let editing {
                Text("この回を含む\(planStore.occurrencesFrom(editing).count)件に、変更した項目だけが反映されます。個別に変更した回は保持されます（この回自身には反映されます）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("変更する範囲", systemImage: "repeat")
        } footer: {
            Text("繰り返しの規則・開始日・回数は変更できません。変える場合は削除して作り直してください。")
        }
    }

    private var dateSection: some View {
        Section {
            if editingSeries == nil || editScope == .occurrence {
                DatePicker(selection: $date, displayedComponents: .date) {
                    Label(editing == nil && recurrenceKind != nil ? "初回の日付" : "日付",
                          systemImage: "calendar")
                }
            } else {
                // シリーズ全体・この回以降の変更では、日付は対象外
                HStack {
                    Label("日付", systemImage: "calendar")
                    Spacer()
                    Text(editScope == .series ? "全体変更の対象外" : "この回以降の変更では対象外")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("時間帯", systemImage: "clock")
                Picker("", selection: $timeBand) {
                    ForEach(TimeBand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("行く度合い", systemImage: "pawprint")
                Picker("", selection: $level) {
                    ForEach(AttendanceLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    /// 繰り返しの設定（新規作成時のみ）。種類と回数を選ぶと、
    /// 保存前に生成される全日付をプレビュー表示する。
    private var recurrenceSection: some View {
        Section {
            Picker("", selection: $recurrenceKind) {
                Text("なし").tag(nil as RecurrenceKind?)
                Text("毎週").tag(RecurrenceKind.weekly as RecurrenceKind?)
                Text("同日").tag(RecurrenceKind.monthlyDay as RecurrenceKind?)
                Text("第○曜日").tag(RecurrenceKind.monthlyOrdinalWeekday as RecurrenceKind?)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("recurrencePicker")
            if let kind = recurrenceKind {
                Text(recurrenceDetailText(kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $occurrenceCount) {
                    ForEach(RecurrenceGenerator.allowedCounts, id: \.self) { count in
                        Text("\(count)回").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("occurrenceCountPicker")
                if !previewDates.isEmpty {
                    Text("全\(previewDates.count)回")
                        .font(.subheadline)
                        .bold()
                    ForEach(previewDates, id: \.self) { day in
                        Text(Self.dateLabel(day)).font(.subheadline)
                    }
                    if let last = previewDates.last {
                        Text("最終日は \(Self.dateLabel(last)) です")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("繰り返し", systemImage: "repeat")
        } footer: {
            if let text = recurrenceFooterText {
                Text(text)
            }
        }
    }

    private static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    /// 選択中の日付を基準にした、繰り返しの具体的な読み（例：毎月第1木曜日）
    /// 規則の解釈は生成・保存と必ず同じ暦（グレゴリオ暦・Asia/Tokyo）で読む（R6）
    private func recurrenceDetailText(_ kind: RecurrenceKind) -> String {
        let weekday = WanMapCalendar.shared.component(.weekday, from: date)
        let weekdayName = Self.weekdayNames[weekday - 1]
        switch kind {
        case .weekly:
            return "毎週\(weekdayName)曜日"
        case .monthlyDay:
            return "毎月\(WanMapCalendar.shared.component(.day, from: date))日"
        case .monthlyOrdinalWeekday:
            return "毎月第\(selectedOrdinal)\(weekdayName)曜日"
        }
    }

    /// 選択した日付が「第○曜日」の何番目か
    private var selectedOrdinal: Int {
        (WanMapCalendar.shared.component(.day, from: date) - 1) / 7 + 1
    }

    private var recurrenceFooterText: String? {
        switch recurrenceKind {
        case .monthlyDay:
            return "その月にない日は、月末になります"
        case .monthlyOrdinalWeekday where selectedOrdinal == 5:
            let weekday = WanMapCalendar.shared.component(.weekday, from: date)
            return "第5曜日がない月は、その月の最後の\(Self.weekdayNames[weekday - 1])曜日になります"
        default:
            return nil
        }
    }

    /// 繰り返しを選んだ時に生成される開催日（プレビュー用）
    private var previewDates: [Date] {
        guard let kind = recurrenceKind else { return [] }
        let rule = RecurrenceRule(kind: kind, startDate: date, calendar: WanMapCalendar.shared)
        return RecurrenceGenerator.dates(rule: rule, start: date,
                                         count: occurrenceCount, calendar: WanMapCalendar.shared) ?? []
    }

    private static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = WanMapCalendar.shared
        f.timeZone = WanMapCalendar.shared.timeZone
        f.dateFormat = "M月d日（EEE）"
        return f.string(from: date)
    }

    private var dogSection: some View {
        Section {
            TextField("犬の名前", text: $dogName)
        } header: {
            Label("犬の名前", systemImage: "pawprint.fill")
        }
    }

    /// 締切を直接編集できる場面かどうか。
    /// 締切は各回で個別に設定するものなので、繰り返しの新規作成と
    /// シリーズ全体・この回以降の変更では扱わない（各回だけの変更では従来どおり編集できる）。
    private var showsDeadlineControls: Bool {
        if editing != nil {
            return editingSeries == nil || editScope == .occurrence
        }
        return recurrenceKind == nil
    }

    private var typeSection: some View {
        Section {
            Picker("", selection: $isEvent) {
                Text("通常の集まり").tag(false)
                Text("イベント（募集）").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if isEvent {
                if showsDeadlineControls {
                    Toggle("締め切りを設定", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("締め切り", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }
                } else {
                    Text("締め切りは各回の予定で個別に設定できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("予定のタイプ", systemImage: "ticket")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: $hidesOwnLocation) {
                Label("この予定では自分の位置を見せない", systemImage: "eye.slash")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                guard let editing else { return }
                if editing.seriesID != nil {
                    // シリーズの子は範囲を選んでから消す（日別一覧のスワイプ削除と共通）
                    // 対象を先に入れてから表示する（ダイアログ側はこの順序を前提とする）
                    deletionTarget = editing
                    showDeletionDialog = true
                } else {
                    if planStore.remove(editing) {
                        dismiss()
                    } else {
                        presentSaveError("削除を保存できませんでした。")
                    }
                }
            } label: {
                HStack { Spacer(); Label("この予定を削除", systemImage: "trash"); Spacer() }
            }
        }
    }

    /// 対象範囲の切り替えに合わせて、入力欄をその範囲の内容で読み直す
    /// （この回だけ＝その回の予定、シリーズ全体＝親の共通内容。
    ///   個別回の例外的な内容を、シリーズ全体の初期値にはしない）
    private func applyScope(_ scope: PlanEditScope) {
        guard let editing, let series = editingSeries else { return }
        switch scope {
        case .occurrence:
            loadFields(from: editing)
        case .following, .series:
            // どちらの初期値もシリーズの共通内容（対象回の個別内容は持ち込まない）
            loadFields(from: series.template)
        }
    }

    private func loadFields(from plan: Plan) {
        date = plan.date
        timeBand = plan.timeBand
        level = plan.level
        dogName = plan.dogName ?? ""
        isEvent = plan.isEvent
        hasDeadline = plan.eventDeadline != nil
        deadline = plan.eventDeadline ?? plan.date
        hidesOwnLocation = plan.hidesOwnLocation
        placeQuery = plan.placeName
        selectedFacility = nil
        selectedUserPlace = nil
        resolvePlace(named: plan.placeName,
                     savedLatitude: plan.latitude, savedLongitude: plan.longitude)
    }

    private func loadFields(from template: PlanTemplate) {
        // シリーズ全体編集の基準は、最初に読み込んだ親の保存済み場所の控え（R5）
        if seriesPlaceSnapshot == nil {
            seriesPlaceSnapshot = SavedPlace(name: template.placeName,
                                             latitude: template.latitude,
                                             longitude: template.longitude)
        }
        timeBand = template.timeBand
        level = template.level
        dogName = template.dogName ?? ""
        isEvent = template.isEvent
        hasDeadline = false
        hidesOwnLocation = template.hidesOwnLocation
        placeQuery = template.placeName
        selectedFacility = nil
        selectedUserPlace = nil
        resolvePlace(named: template.placeName,
                     savedLatitude: template.latitude, savedLongitude: template.longitude)
    }

    /// 編集時、保存済みの場所名が自分の場所／登録施設と一致したら選択状態を復元する
    private func resolvePlaceFromEditingPlan() {
        guard !hasSelection, let editing, !editing.placeName.isEmpty else { return }
        resolvePlace(named: editing.placeName,
                     savedLatitude: editing.latitude, savedLongitude: editing.longitude)
    }

    /// 場所名が自分の場所／登録施設と一致したら選択状態を復元する
    /// （自分で追加した情報の方が優先度が高いので、自分の場所から先に照合する）。
    /// ただし復元は、候補の座標が保存済みの座標と一致する時だけ（R5）：
    /// 名前が同じでも座標の違う登録場所を、保存済みの座標と暗黙に差し替えない。
    private func resolvePlace(named name: String, savedLatitude: Double?, savedLongitude: Double?) {
        guard !hasSelection, !name.isEmpty else { return }
        let target = FacilityStore.normalize(name)
        if let place = userPlaceStore.places.first(where: {
            FacilityStore.normalize($0.name) == target
        }) {
            guard place.latitude == savedLatitude, place.longitude == savedLongitude else { return }
            selectedUserPlace = place
            placeQuery = place.name
            return
        }
        if let facility = facilityStore.facilities.first(where: {
            FacilityStore.normalize($0.displayName) == target || FacilityStore.normalize($0.name) == target
        }) {
            guard facility.lat == savedLatitude, facility.lng == savedLongitude else { return }
            selectedFacility = facility
            placeQuery = facility.displayName
        }
    }

    /// 保存成功時の締め：完了フィードバック（音＋触覚）を1回だけ出してから閉じる。
    /// Store の保存結果が成功の時だけ通る経路に置く。失敗時は呼ばず、
    /// フォームは開いたままエラー表示が正しいフィードバックになる。
    private func completeSave() {
        feedback.completion()
        dismiss()
    }

    /// 保存・削除の最終失敗の提示：アラート表示と失敗の触覚を必ずセットにする
    /// （第2単位、2026-11-12。線引きは DESIGN_PRINCIPLES.md の触覚の項）。
    private func presentSaveError(_ message: String) {
        saveErrorMessage = message
        feedback.error()
    }

    private func save() {
        let day = WanMapCalendar.shared.startOfDay(for: date)

        // この保存で基準にする「保存済みの場所」（R5）。スコープごとに切り替える：
        // シリーズ全体・この回以降＝親の共通内容の控え、この回だけ／通常編集＝編集中の予定の控え。
        let isSeriesScope = editing?.seriesID != nil && editScope == .series
        let isFollowingScope = editing?.seriesID != nil && editScope == .following
        let baseline: SavedPlace?
        if isSeriesScope || isFollowingScope, let series = editingSeries {
            baseline = seriesPlaceSnapshot
                ?? SavedPlace(name: series.template.placeName,
                              latitude: series.template.latitude,
                              longitude: series.template.longitude)
        } else if let editing {
            baseline = SavedPlace(name: editing.placeName,
                                  latitude: editing.latitude, longitude: editing.longitude)
        } else {
            baseline = nil
        }

        let placeName: String
        let latitude: Double?
        let longitude: Double?
        if let place = selectedUserPlace {
            placeName = place.name
            latitude = place.latitude
            longitude = place.longitude
        } else if let facility = selectedFacility {
            placeName = facility.displayName
            latitude = facility.lat
            longitude = facility.lng
        } else {
            // 候補から選んでいない場合は、名前が控えと同一の時だけ座標を引き継ぐ。
            // 名前の照合で、別の登録場所の座標を暗黙に持ってくることはしない（R5）。
            placeName = placeQuery.trimmingCharacters(in: .whitespaces)
            if let baseline, baseline.name == placeName {
                latitude = baseline.latitude
                longitude = baseline.longitude
            } else {
                latitude = nil
                longitude = nil
            }
        }

        let trimmedDog = dogName.trimmingCharacters(in: .whitespaces)
        let resolvedDogName: String? = trimmedDog.isEmpty ? nil : trimmedDog

        // シリーズ全体の共通内容変更：日付と締切は対象外なので、雛形だけを組み立てて渡す
        // （変わった項目だけが全回へ反映される。PlanStore.updateSeriesContent 側で差分を取る）
        if isSeriesScope, let series = editingSeries {
            let newTemplate = PlanTemplate(
                personName: resolvedDogName ?? "自分",
                dogName: resolvedDogName,
                placeName: placeName, latitude: latitude, longitude: longitude,
                timeBand: timeBand, level: level, isEvent: isEvent,
                hidesOwnLocation: hidesOwnLocation
            )
            if planStore.updateSeriesContent(seriesID: series.id, newTemplate: newTemplate) {
                completeSave()
            } else {
                presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
            }
            return
        }

        // この回以降の変更：日付と締切は対象外。雛形の差分だけが後半へ反映され、
        // 個別に変更した回は保持される（PlanStore.updateFollowing が分割と適用を行う）
        if isFollowingScope, let editing {
            let newTemplate = PlanTemplate(
                personName: resolvedDogName ?? "自分",
                dogName: resolvedDogName,
                placeName: placeName, latitude: latitude, longitude: longitude,
                timeBand: timeBand, level: level, isEvent: isEvent,
                hidesOwnLocation: hidesOwnLocation
            )
            if planStore.updateFollowing(editing, newTemplate: newTemplate) {
                completeSave()
            } else {
                presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
            }
            return
        }

        var plan = editing ?? Plan(
            id: UUID(), personName: "", dogName: nil, placeName: "",
            latitude: nil, longitude: nil, date: day,
            timeBand: timeBand, level: level,
            isEvent: false, eventDeadline: nil, isPresence: false, createdAt: Date()
        )
        plan.personName = editing?.personName ?? (trimmedDog.isEmpty ? "自分" : trimmedDog)
        plan.dogName = resolvedDogName
        plan.placeName = placeName
        plan.latitude = latitude
        plan.longitude = longitude
        plan.date = day
        plan.timeBand = timeBand
        plan.level = level
        plan.isEvent = isEvent
        plan.eventDeadline = (isEvent && hasDeadline) ? deadline : nil
        plan.hidesOwnLocation = hidesOwnLocation

        if editing == nil {
            if let kind = recurrenceKind {
                // 繰り返し：全回を実体化してシリーズとして保存する。
                // 締切は各回で個別に設定するものなので、ここでは付けない。
                plan.eventDeadline = nil
                let rule = RecurrenceRule(kind: kind, startDate: day, calendar: WanMapCalendar.shared)
                if planStore.addSeries(rule: rule, occurrenceCount: occurrenceCount,
                                       templatePlan: plan) != nil {
                    completeSave()
                } else {
                    presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
                }
            } else if planStore.add(plan) {
                completeSave()
            } else {
                presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
            }
        } else if editing?.seriesID != nil {
            if planStore.updateOccurrence(plan) {
                completeSave()
            } else {
                presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
            }
        } else if planStore.update(plan) {
            completeSave()
        } else {
            presentSaveError("保存できませんでした。入力内容はそのまま残っています。")
        }
    }
}
