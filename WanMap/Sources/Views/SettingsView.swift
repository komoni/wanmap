import SwiftUI

/// 設定画面
/// - 自分のID（表示ID・内部ID）の確認
/// - 「見せない相手」リスト：友達画面と同じ FriendStore のデータを触るので連動する
/// - Instagram連携はモックである旨を正直に表示する
/// - 位置情報の扱い（端末内のみ・「今ここ」は2時間で消去）の説明と非表示モード
/// - ローカルデータ（予定・友達・追加した場所）のリセット（確認ダイアログ付き）
struct SettingsView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(PlanStore.self) private var planStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirm = false
    @State private var resetDone = false

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
                    Text("連携はモックです。本物のInstagramとは接続していません（連携すると表示IDがユーザーネームになります）。")
                }

                Section {
                    Toggle("自分の位置を表示しない", isOn: $location.hideMode)
                } header: {
                    Text("位置情報")
                } footer: {
                    Text("位置はこの端末の中だけに保存され、外に送られることはありません。「今ここ」は置いてから2時間で自動的に消え、新しい位置を置くと前の場所は残りません。")
                }

                Section("データ") {
                    Button("データをリセット", role: .destructive) {
                        showResetConfirm = true
                    }
                    if resetDone {
                        Text("リセットしました")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("データをリセット", isPresented: $showResetConfirm) {
                Button("すべて消す", role: .destructive) {
                    planStore.resetAllData()
                    friendStore.resetAll()
                    userPlaceStore.resetAll()
                    resetDone = true
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この端末に保存した予定・友達・追加した場所のデータをすべて消します。自分のIDも新しく作り直されます。")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(FriendStore.preview)
        .environment(PlanStore(samplePlans: []))
        .environment(UserPlaceStore(samplePlaces: []))
        .environment(LocationService())
}
