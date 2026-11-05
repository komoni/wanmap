import SwiftUI

/// 予定の追加・編集フォーム（共通シート）
///
/// 仕様（決定済み）：
/// - 場所は登録済み施設からの候補検索で選ぶか、住所テキストとして直接入力する（緯度経度の数値入力はしない）
/// - 自分で追加した場所（UserPlace）も候補に出し、公式施設より優先して先に並べる。選ぶと座標付きの予定になる
/// - 場所のエリア（地域）入力欄は作らない
/// - 「自分の位置を見せない」トグルはこのフォーム内にだけ置く（カレンダー／地図のバーには置かない）
/// - 犬の名前は前回使った名前を初期値にする（PlanStore.lastDogName）
struct PlanFormView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(FacilityStore.self) private var facilityStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
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

    var body: some View {
        NavigationStack {
            Form {
                placeSection
                dateSection
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
                }
            }
            .onAppear(perform: resolvePlaceFromEditingPlan)
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

    private var dateSection: some View {
        Section {
            DatePicker(selection: $date, displayedComponents: .date) {
                Label("日付", systemImage: "calendar")
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

    private var dogSection: some View {
        Section {
            TextField("犬の名前", text: $dogName)
        } header: {
            Label("犬の名前", systemImage: "pawprint.fill")
        }
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
                Toggle("締め切りを設定", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("締め切り", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
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
                if let editing { planStore.remove(editing) }
                dismiss()
            } label: {
                HStack { Spacer(); Label("この予定を削除", systemImage: "trash"); Spacer() }
            }
        }
    }

    /// 編集時、保存済みの場所名が自分の場所／登録施設と一致したら選択状態を復元する
    /// （自分で追加した情報の方が優先度が高いので、自分の場所から先に照合する）
    private func resolvePlaceFromEditingPlan() {
        guard !hasSelection, let editing, !editing.placeName.isEmpty else { return }
        let target = FacilityStore.normalize(editing.placeName)
        if let place = userPlaceStore.places.first(where: {
            FacilityStore.normalize($0.name) == target
        }) {
            selectedUserPlace = place
            placeQuery = place.name
            return
        }
        if let facility = facilityStore.facilities.first(where: {
            FacilityStore.normalize($0.displayName) == target || FacilityStore.normalize($0.name) == target
        }) {
            selectedFacility = facility
            placeQuery = facility.displayName
        }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: date)
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
            placeName = placeQuery.trimmingCharacters(in: .whitespaces)
            if let editing, editing.placeName == placeName {
                latitude = editing.latitude
                longitude = editing.longitude
            } else {
                latitude = nil
                longitude = nil
            }
        }

        let trimmedDog = dogName.trimmingCharacters(in: .whitespaces)
        var plan = editing ?? Plan(
            id: UUID(), personName: "", dogName: nil, placeName: "",
            latitude: nil, longitude: nil, date: day,
            timeBand: timeBand, level: level,
            isEvent: false, eventDeadline: nil, isPresence: false, createdAt: Date()
        )
        plan.personName = editing?.personName ?? (trimmedDog.isEmpty ? "自分" : trimmedDog)
        plan.dogName = trimmedDog.isEmpty ? nil : trimmedDog
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
            planStore.add(plan)
        } else {
            planStore.update(plan)
        }
        dismiss()
    }
}
