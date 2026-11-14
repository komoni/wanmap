import SwiftUI
import CoreLocation

/// 場所の追加・編集フォーム
///
/// 仕様（決定済み）：
/// - 地点は地図の中心ピンで先に決めてから開く。緯度経度の数値入力欄は作らない。
/// - 編集では地点は変えず、名前・種別・住所・公開範囲・メモだけを触る。
/// - 公開範囲の初期値は「招待した人だけ」。共有されるのは場所名だけで、座標は公開されない。
/// - 名前が未入力でも仮名で登録できる（とりあえずピン立てして後で編集する
///   使い方のため。実機フィードバック⑫、2026-11-14）
struct UserPlaceFormView: View {
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(\.dismiss) private var dismiss

    let editing: UserPlace?
    /// 新規追加の時だけ使う、地図で決めた座標（編集時は nil）
    let coordinate: CLLocationCoordinate2D?

    @State private var name: String
    @State private var kind: UserPlaceKind
    @State private var address: String
    @State private var visibility: PlaceVisibility
    @State private var memo: String

    init(editing: UserPlace?, coordinate: CLLocationCoordinate2D? = nil) {
        self.editing = editing
        self.coordinate = coordinate
        _name = State(initialValue: editing?.name ?? "")
        _kind = State(initialValue: editing?.kind ?? .dogRun)
        _address = State(initialValue: editing?.address ?? "")
        _visibility = State(initialValue: editing?.visibility ?? .inviteOnly)
        _memo = State(initialValue: editing?.memo ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("場所の名前", text: $name)
                    Picker("", selection: $kind) {
                        ForEach(UserPlaceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Label("名前と種別", systemImage: "mappin.and.ellipse")
                } footer: {
                    Text("名前は空欄でも登録できます（仮の名前が付きます。後から編集で直せます）")
                }

                Section {
                    TextField("住所（任意）", text: $address)
                } header: {
                    Label("住所", systemImage: "house")
                }

                Section {
                    Picker("公開範囲", selection: $visibility) {
                        ForEach(PlaceVisibility.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    Label("公開範囲", systemImage: "eye")
                } footer: {
                    Text("共有されるのは場所名だけです。座標そのものが公開されることはありません。")
                }

                Section {
                    TextField("メモ", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                } header: {
                    Label("メモ", systemImage: "note.text")
                }

                if editing != nil { deleteSection }
            }
            .navigationTitle(editing == nil ? "場所を追加" : "場所を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 名前が空でも保存できる（save 側で仮名を付ける）
                    Button("保存") { save() }
                        .bold()
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                if let editing { userPlaceStore.remove(editing) }
                dismiss()
            } label: {
                HStack { Spacer(); Label("この場所を削除", systemImage: "trash"); Spacer() }
            }
        }
    }

    /// 保存に使う名前。未入力なら仮名（「仮の場所」、重なれば番号付き）を付ける
    private var resolvedName: String {
        if !trimmedName.isEmpty { return trimmedName }
        let base = "仮の場所"
        let existing = Set(userPlaceStore.places.map(\.name))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base)\(number)") { number += 1 }
        return "\(base)\(number)"
    }

    private func save() {
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
        if var place = editing {
            place.name = resolvedName
            place.kind = kind
            place.address = trimmedAddress.isEmpty ? nil : trimmedAddress
            place.visibility = visibility
            place.memo = trimmedMemo.isEmpty ? nil : trimmedMemo
            userPlaceStore.update(place)
        } else if let coordinate {
            let place = UserPlace(
                id: UUID(), name: resolvedName, kind: kind,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                visibility: visibility,
                memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                createdAt: Date()
            )
            userPlaceStore.add(place)
        }
        dismiss()
    }
}

/// ユーザーが追加した場所の情報シート（公式施設のシートと同じ流儀）
/// - ユーザー登録である旨と公開範囲を表示する。編集・削除はここから。
/// - 出典は「ユーザー提供位置情報」と一般化して表記する（個人名は出さない）。
struct UserPlaceSheet: View {
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss

    let place: UserPlace
    @State private var showEditForm = false
    @State private var showPlanForm = false
    @State private var showDeleteConfirm = false

    /// 編集で内容が変わっても追従できるよう、保存済みの最新を引く
    private var current: UserPlace {
        userPlaceStore.places.first { $0.id == place.id } ?? place
    }

    /// Googleマップ：座標で開く
    private var googleMapsURL: URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(current.latitude),\(current.longitude)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(current.kind.markerEmoji)
                    Text(current.name).font(.title3).bold()
                }
                Text("自分で登録した場所")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                row("種別", current.kind.rawValue)
                if let address = current.address, !address.isEmpty { row("住所", address) }
                row("公開範囲", current.visibility.rawValue)
                if let memo = current.memo, !memo.isEmpty { row("メモ", memo) }

                HStack {
                    if let url = googleMapsURL {
                        Link("Googleマップで開く", destination: url)
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                Text("いつ行く予定").font(.subheadline).bold()
                Button {
                    showPlanForm = true
                } label: {
                    Label("予定を入れる", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)

                Divider()

                HStack {
                    Button {
                        showEditForm = true
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Text("出典：ユーザー提供位置情報")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("この場所が共有される時、公開されるのは場所名だけです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .sheet(isPresented: $showEditForm) {
            UserPlaceFormView(editing: current)
        }
        .sheet(isPresented: $showPlanForm) {
            PlanFormView(editing: nil, defaultDogName: planStore.lastDogName,
                         initialUserPlace: current)
        }
        .confirmationDialog("この場所を削除しますか", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                userPlaceStore.remove(place)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }
}
