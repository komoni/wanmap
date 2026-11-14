import SwiftUI

/// 設定画面
/// - 自分のID（表示ID・内部ID）の確認
/// - 予定チップの色（テーマ設定 ThemeStore。タップで即変更・即保存）
/// - 見た目の比較案（ボタンの色／カレンダーヘッダーの段数。AppearanceStore）
/// - 音と触覚（効果音・触覚のON/OFFと試聴。FeedbackSettings／FeedbackService）
/// - 「見せない相手」リスト：友達画面と同じ FriendStore のデータを触るので連動する
/// - 将来機能の仮項目（ブロックした人・アカウント削除）：
///   項目だけ先に置き、タップでは「準備中」を正直に表示する（嘘の動作はしない）
/// - Instagram連携は行わない（公式APIの制約により2026-11-13に不採用を決定）
/// - 位置情報の扱い（端末内のみ・「今ここ」は2時間で消去）の説明と非表示モード
/// - ローカルデータ（予定・友達・追加した場所）のリセット（確認ダイアログ付き）
struct SettingsView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(AppearanceStore.self) private var appearanceStore
    @Environment(FeedbackSettings.self) private var feedbackSettings
    @Environment(FeedbackService.self) private var feedback
    @Environment(BreedStore.self) private var breedStore
    @Environment(MarkerSettings.self) private var markerSettings
    @Environment(PlanStore.self) private var planStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    /// 自分の犬の名前の入力欄（確定タイミングでのみ FriendStore へ反映する）
    @State private var dogNameText = ""
    /// 名前入力欄のフォーカス（キーボードの「完了」で閉じるために使う）
    @FocusState private var dogNameFocused: Bool
    @State private var showResetConfirm = false
    /// 仮項目（将来機能）をタップした時の「準備中」表示
    @State private var showComingSoon = false
    /// リセット結果の表示文。失敗を成功として見せないため、結果に応じて出し分ける
    @State private var resetMessage: String?
    @State private var resetHadFailure = false

    var body: some View {
        @Bindable var location = location
        @Bindable var themeStore = themeStore
        @Bindable var appearanceStore = appearanceStore
        @Bindable var feedbackSettings = feedbackSettings
        @Bindable var markerSettings = markerSettings
        NavigationStack {
            List {
                Section("自分のID") {
                    HStack {
                        Text("表示ID")
                        Spacer()
                        Text(friendStore.me.publicId)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("内部ID")
                        Spacer()
                        Text(friendStore.me.internalId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // 自分の犬（任意設定）。初回に強制はしない。犬種・毛色は
                // 地図の犬種アイコンの材料になり、未設定の犬はミックスで表示される。
                Section {
                    HStack(spacing: 12) {
                        BreedIconView(asset: breedStore.markerIconAsset(
                            breedId: friendStore.me.breedId,
                            colorId: friendStore.me.dogColorId), size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friendStore.me.dogName ?? "名前は未設定")
                                .font(.headline)
                            Text(myDogSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("名前")
                        TextField("犬の名前", text: $dogNameText)
                            .multilineTextAlignment(.trailing)
                            .focused($dogNameFocused)
                            .onSubmit { commitDogName() }
                            .accessibilityIdentifier("myDogNameField")
                    }
                    NavigationLink {
                        BreedPickerView(currentBreedId: friendStore.me.breedId) { breedId in
                            friendStore.updateMyDogBreed(breedId: breedId)
                        }
                    } label: {
                        HStack {
                            Text("犬種")
                            Spacer()
                            Text(myBreed?.name ?? "未設定")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("breedPickerLink")
                    if let breed = myBreed, !breed.colors.isEmpty {
                        LazyVGrid(columns: colorColumns, spacing: 8) {
                            ForEach(breed.colors) { color in
                                BreedColorCell(
                                    color: color,
                                    isSelected: friendStore.me.dogColorId == color.id
                                ) {
                                    friendStore.updateMyDogColor(colorId: color.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if friendStore.me.dogColorId != nil {
                            Button("毛色を設定しない") {
                                friendStore.updateMyDogColor(colorId: nil)
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("自分の犬")
                } footer: {
                    Text("任意の設定です。設定しなくても今まで通り使えます。犬種を選ぶと、地図の「犬種アイコン」で自分の犬の顔が出ます。")
                }

                Section {
                    Picker("チップの種類", selection: $markerSettings.chipStyle) {
                        ForEach(MarkerChipStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("markerChipStylePicker")
                } header: {
                    Text("地図の表示")
                } footer: {
                    Text("地図に出る予定・今ここのチップの見た目です。「犬種アイコン」では、犬種が未設定の犬はミックスのアイコンで表示されます。")
                }

                Section("デザイン") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("予定チップの色")
                        HStack(spacing: 14) {
                            ForEach(ThemeStore.chipColorPresets) { preset in
                                chipSwatch(preset)
                            }
                        }
                        Text(themeStore.chipColorPreset.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // 見た目の比較案（デザイン・気持ちよさ第一弾）。
                // 本人がスクショで見比べて選ぶための切り替えで、選ばれた方を後に既定化する。
                Section {
                    Picker("テーマ", selection: $themeStore.appTheme) {
                        ForEach(ThemeStore.AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .accessibilityIdentifier("appThemePicker")
                    Picker("ボタンの色", selection: $appearanceStore.buttonVariant) {
                        ForEach(AppearanceStore.ButtonVariant.allCases, id: \.self) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    Picker("カレンダーのヘッダー", selection: $appearanceStore.headerLayout) {
                        ForEach(AppearanceStore.HeaderLayout.allCases, id: \.self) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                } header: {
                    Text("見た目")
                } footer: {
                    Text("テーマはカレンダー画面の配色をまとめて切り替えます（地図など他の画面は今の配色のままです）。「ボタンの色」はテーマがパステルの時に効きます。")
                }

                Section {
                    Toggle("効果音", isOn: $feedbackSettings.soundEnabled)
                    Toggle("触覚フィードバック", isOn: $feedbackSettings.hapticsEnabled)
                    Button("効果を試す") { feedback.preview() }
                } header: {
                    Text("音と触覚")
                } footer: {
                    Text("効果音はサイレントモードでは鳴りません。触覚設定はWanMapが追加する振動に適用されます（端末や標準部品の振動までは止めません）。「効果を試す」は設定にかかわらず1回だけ鳴ります。")
                }

                Section {
                    ForEach(friendStore.friends) { relation in
                        HStack {
                            BreedIconView(asset: breedStore.markerIconAsset(
                                breedId: relation.user.breedId,
                                colorId: relation.user.dogColorId), size: 28)
                            Text(friendDisplayName(relation.user))
                            Spacer()
                            Toggle("見せない",
                                   isOn: hideFromMeBinding(store: friendStore,
                                                           internalId: relation.user.internalId))
                                .font(.caption)
                                .fixedSize()
                        }
                    }
                    if friendStore.friends.isEmpty {
                        Text("友達がいません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("見せない相手")
                } footer: {
                    Text("ここでオンにした相手には、自分の位置と存在が見えません。友達画面の「見せない」と同じリストです。")
                }

                // プライバシー・安全（仮項目）。ブロックとアカウント削除は
                // アカウント機能の提供に合わせて実装する。今は置き場だけ作り、
                // タップでは「準備中」を正直に表示する。
                Section {
                    Button {
                        showComingSoon = true
                    } label: {
                        HStack {
                            Text("ブロックした人")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("0件")
                                .foregroundStyle(.secondary)
                            comingSoonBadge
                        }
                    }
                    .accessibilityIdentifier("blockedPeopleRow")
                    Button {
                        showComingSoon = true
                    } label: {
                        HStack {
                            Text("アカウントを削除")
                                .foregroundStyle(.primary)
                            Spacer()
                            comingSoonBadge
                        }
                    }
                    .accessibilityIdentifier("deleteAccountRow")
                } header: {
                    Text("プライバシー・安全")
                } footer: {
                    Text("ブロックとアカウント削除は、アカウント機能の提供に合わせて使えるようになります。")
                }

                Section {
                    Toggle("自分の位置を表示しない", isOn: $location.hideMode)
                    HStack {
                        Text("位置情報の許可")
                        Spacer()
                        Text(authorizationStatusText)
                            .foregroundStyle(.secondary)
                    }
                    if location.authorizationStatus == .authorizedWhenInUse {
                        Button("アプリを閉じている間の移動も検知する（常に許可）") {
                            Task { await location.requestAlwaysUpgrade() }
                        }
                    }
                } header: {
                    Text("位置情報")
                } footer: {
                    Text(locationFooterText)
                }

                Section("データ") {
                    Button("データをリセット", role: .destructive) {
                        showResetConfirm = true
                    }
                    if let resetMessage {
                        Text(resetMessage)
                            .font(.caption)
                            .foregroundStyle(resetHadFailure ? Color.red : Color.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .onAppear { dogNameText = friendStore.me.dogName ?? "" }
            .onChange(of: friendStore.me.internalId) { _, _ in
                // データリセットで自分が作り直されたら入力欄も追随させる
                dogNameText = friendStore.me.dogName ?? ""
            }
            .onDisappear { commitDogName() }
            .onChange(of: location.hideMode) { _, hidden in
                // 非表示をやめたら、本人の操作として取得を再開する
                if !hidden { location.requestPermissionAndStart() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .toolbar {
                // キーボードの「完了」（キーボード表示中だけ出る）。
                // 名前入力欄はキーボードに隠れて閉じにくい、という実機フィードバック対応。
                // 押したら名前を確定してからキーボードを閉じる
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        commitDogName()
                        dogNameFocused = false
                    }
                }
            }
            .confirmationDialog("データをリセット", isPresented: $showResetConfirm) {
                Button("すべて消す", role: .destructive) {
                    let result = planStore.resetAllData()
                    friendStore.resetAll()
                    userPlaceStore.resetAll()
                    if !result.fileReset {
                        // 予定ファイル自体を初期化できなかった場合は成功として見せない
                        resetHadFailure = true
                        resetMessage = "予定のリセットに失敗しました：" + result.failures.joined(separator: "／")
                    } else if result.failures.isEmpty {
                        resetHadFailure = false
                        resetMessage = "リセットしました"
                    } else {
                        // 本体の初期化はできたが、退避ファイルの削除などで失敗が残った
                        resetHadFailure = true
                        resetMessage = "リセットしました（ただし一部失敗：" + result.failures.joined(separator: "／") + "）"
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この端末に保存した予定・友達・追加した場所のデータをすべて消します。自分のIDも新しく作り直されます。")
            }
            .alert("準備中", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("この機能は準備中です。")
            }
        }
    }

    /// 仮項目の右端に出す「準備中」バッジ（将来機能の置き場であることを見た目でも伝える）
    private var comingSoonBadge: some View {
        Text("準備中")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }

    // MARK: - 自分の犬まわり

    private var myBreed: Breed? { breedStore.breed(id: friendStore.me.breedId) }

    private var myDogSummary: String {
        guard let breed = myBreed else { return "犬種は未設定（ミックスで表示）" }
        if let color = breed.color(id: friendStore.me.dogColorId) {
            return "\(breed.name)・\(color.name)"
        }
        return breed.name
    }

    private var colorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 84), spacing: 8)]
    }

    /// 名前入力の確定（改行・画面を閉じる時に呼ぶ）。変わっていない時は何もしない
    private func commitDogName() {
        if dogNameText != (friendStore.me.dogName ?? "") {
            friendStore.updateMyDogName(dogNameText)
        }
    }

    /// チップ色のスウォッチ（円）。選択中はコーラルのリング＋チェックで示す。
    /// タップで即変更・即保存される（ThemeStore 側で UserDefaults に書く）。
    private func chipSwatch(_ preset: ThemeStore.ChipColorPreset) -> some View {
        let isSelected = themeStore.chipColorPreset.id == preset.id
        return Button {
            themeStore.selectChipColor(id: preset.id)
        } label: {
            Circle()
                .fill(preset.color)
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanStyle.cocoa)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? WanStyle.coral : Color.black.opacity(0.08),
                                      lineWidth: isSelected ? 2.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// 許可状態の表示名（現状を正直に書く。許可されていないのに
    /// バックグラウンドで動くとは書かない）
    private var authorizationStatusText: String {
        switch location.authorizationStatus {
        case .authorizedAlways: return "常に許可"
        case .authorizedWhenInUse: return "アプリ使用中のみ"
        case .denied, .restricted: return "許可されていません"
        case .notDetermined: return "未設定"
        @unknown default: return "不明"
        }
    }

    private var locationFooterText: String {
        var text = "位置はこの端末の中だけに保存され、外に送られることはありません。「今ここ」は置いてから2時間で自動的に消え、新しい位置を置くと前の場所は残りません。「今ここ」は本人が地図で置いた時だけ動き、移動に自動ではついてきません。"
        switch location.authorizationStatus {
        case .authorizedAlways:
            text += "「常に許可」なので、アプリを閉じている間も大きな移動を検知して現在地を更新できます（常時GPSではなく、大きな移動の検知ベースです）。"
        case .authorizedWhenInUse:
            text += "今の許可では、現在地が更新されるのはアプリを開いている間だけです。閉じている間の移動も検知するには「常に許可」が必要です。"
        case .denied, .restricted:
            text += "位置情報が許可されていないため、「今ここ」は使えません。端末の設定アプリから許可できます。"
        default:
            break
        }
        return text
    }
}

#Preview {
    SettingsView()
        .environment(FriendStore.preview)
        .environment(BreedStore())
        .environment(MarkerSettings(defaults: UserDefaults(suiteName: "preview-marker")!))
        .environment(ThemeStore())
        .environment(AppearanceStore())
        .environment(FeedbackSettings())
        .environment(FeedbackService(settings: FeedbackSettings()))
        .environment(PlanStore(samplePlans: []))
        .environment(UserPlaceStore(samplePlaces: []))
        .environment(LocationService())
}
