import SwiftUI

/// 設定画面
/// - 自分のID（表示ID・内部ID）の確認
/// - 予定チップの色（テーマ設定 ThemeStore。タップで即変更・即保存）
/// - 「見せない相手」リスト：友達画面と同じ FriendStore のデータを触るので連動する
/// - Instagram連携はモックである旨を正直に表示する
/// - 位置情報の扱い（端末内のみ・「今ここ」は2時間で消去）の説明と非表示モード
/// - ローカルデータ（予定・友達・追加した場所）のリセット（確認ダイアログ付き）
struct SettingsView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(PlanStore.self) private var planStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirm = false
    /// リセット結果の表示文。失敗を成功として見せないため、結果に応じて出し分ける
    @State private var resetMessage: String?
    @State private var resetHadFailure = false

    var body: some View {
        @Bindable var location = location
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

                Section {
                    ForEach(friendStore.friends) { relation in
                        HStack {
                            Text("🐶 \(friendDisplayName(relation.user))")
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

                Section {
                    HStack {
                        Text("Instagram連携")
                        Spacer()
                        Text("未連携")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("連携はモックです。本物のInstagramとは接続していません（連携すると表示IDがユーザーネームになります）。投稿の取り込みは、共有シートや文面の貼り付けで本人が持ち込んだものだけです。自動で投稿を取得することはありません。")
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
            .onChange(of: location.hideMode) { _, hidden in
                // 非表示をやめたら、本人の操作として取得を再開する
                if !hidden { location.requestPermissionAndStart() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
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
        .environment(ThemeStore())
        .environment(PlanStore(samplePlans: []))
        .environment(UserPlaceStore(samplePlaces: []))
        .environment(LocationService())
}
