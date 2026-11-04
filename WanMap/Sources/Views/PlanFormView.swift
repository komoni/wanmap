import SwiftUI

/// 予定の追加・編集フォーム（共通シート）
///
/// 仕様（決定済み）：
/// - 場所は登録済み施設からの候補検索で選ぶか、住所テキストとして直接入力する（緯度経度の数値入力はしない）
/// - 場所のエリア（地域）入力欄は作らない
/// - 「自分の位置を見せない」トグルはこのフォーム内にだけ置く（カレンダー／地図のバーには置かない）
/// - 犬の名前は前回使った名前を初期値にする（PlanStore.lastDogName）
struct PlanFormView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(FacilityStore.self) private var facilityStore
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

    /// initialFacility：施設シートから開く時にその施設（名前・座標）を選択済みにする
    init(editing: Plan?, defaultDate: Date = Date(), defaultDogName: String = "",
         initialFacility: Facility? = nil) {
        self.editing = editing
        _date = State(initialValue: editing?.date ?? defaultDate)
        _timeBand = State(initialValue: editing?.timeBand ?? .allDay)
        _level = State(initialValue: editing?.level ?? .going)
        _dogName = State(initialValue: editing?.dogName ?? defaultDogName)
        _isEvent = State(initialValue: editing?.isEvent ?? false)
        _hasDeadline = State(initialValue: editing?.eventDeadline != nil)
        _deadline = State(initialValue: editing?.eventDeadline ?? (editing?.date ?? defaultDate))
        _hidesOwnLocation = State(initialValue: editing?.hidesOwnLocation ?? false)
        _placeQuery = State(initialValue: editing?.placeName ?? initialFacility?.displayName ?? "")
        _selectedFacility = State(initialValue: initialFacility)
    }

    private var candidates: [Facility] {
        guard selectedFacility == nil else { return [] }
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
            .onAppear(perform: resolveFacilityFromEditingPlan)
            .onChange(of: placeQuery) { _, newValue in
                // 手で書き換えたら施設選択は解除する（そのまま住所テキストとして扱う）
                if let facility = selectedFacility, newValue != facility.displayName {
                    selectedFacility = nil
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
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        selectedFacility = nil
                        placeQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(candidates) { facility in
                    Button {
                        selectedFacility = facility
                        placeQuery = facility.displayName
                    } label: {
                        HStack {
                            Image(systemName: "pawprint.fill").foregroundStyle(.orange)
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

    /// 編集時、保存済みの場所名が登録施設と一致したら施設選択状態を復元する
    private func resolveFacilityFromEditingPlan() {
        guard selectedFacility == nil, let editing, !editing.placeName.isEmpty else { return }
        let target = FacilityStore.normalize(editing.placeName)
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
        if let facility = selectedFacility {
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
