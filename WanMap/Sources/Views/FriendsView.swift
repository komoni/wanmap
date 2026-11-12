import SwiftUI
import UIKit

/// 「見せない」トグルの Binding。友達画面と設定画面で共有するが、
/// 実データは FriendStore.relations の1か所だけ（片方の変更がもう片方に即反映される）。
func hideFromMeBinding(store: FriendStore, internalId: String) -> Binding<Bool> {
    Binding(
        get: { store.relations.first { $0.user.internalId == internalId }?.hideFromMe ?? false },
        set: { store.setHide(internalId: internalId, $0) }
    )
}

/// 表示名：犬の名前を優先し、無ければ飼い主名
func friendDisplayName(_ user: AppUser) -> String {
    if let dog = user.dogName, !dog.isEmpty { return dog }
    return user.displayName
}

/// 友達画面（モック）
/// 実通信はまだ無い：検索・申請・承認はすべて端末内のモック動作で完結する。
/// そのことは画面下部の注記で隠さず伝える。
struct FriendsView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(BreedStore.self) private var breedStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showMyQR = false
    @State private var showQRAdd = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                myIdSection
                searchSection
                if !friendStore.incomingRequests.isEmpty {
                    incomingSection
                }
                friendsSection
                Section {
                    Text("友達機能はまだモックです。申請や承認はこの端末の中だけで処理され、実際に相手へは届きません。位置と予定が見えるのは、友達のうち共有に同意した相手だけです（全員には見えません）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("友達")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQRAdd = true } label: {
                        Image(systemName: "qrcode")
                    }
                }
            }
            .sheet(isPresented: $showMyQR) { MyQRView() }
            .sheet(isPresented: $showQRAdd) { QRAddView() }
        }
    }

    private var myIdSection: some View {
        Section("自分のID") {
            VStack(alignment: .leading, spacing: 4) {
                Text(friendStore.me.publicId)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Text("内部ID \(friendStore.me.internalId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(friendStore.me.instagramUsername == nil
                     ? "Instagram未連携のため、アプリ発行IDで表示しています"
                     : "Instagram連携済み")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { showMyQR = true } label: {
                Label("QRコードを表示", systemImage: "qrcode")
            }
        }
    }

    private var searchSection: some View {
        Section("友達を探す") {
            HStack {
                TextField("ID・名前・犬の名前で検索", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            ForEach(friendStore.searchDirectory(searchText)) { user in
                HStack {
                    userRowLabel(user)
                    Spacer()
                    Button("申請") {
                        friendStore.sendRequest(to: user)
                        message = "\(friendDisplayName(user)) さんと友達になりました（モック：自動承認）"
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var incomingSection: some View {
        Section("届いている申請") {
            ForEach(friendStore.incomingRequests) { relation in
                HStack {
                    userRowLabel(relation.user)
                    Spacer()
                    Button("承認") {
                        friendStore.approve(internalId: relation.user.internalId)
                        message = "\(friendDisplayName(relation.user)) さんと友達になりました"
                    }
                    .buttonStyle(.borderedProminent)
                    Button("断る", role: .destructive) {
                        friendStore.reject(internalId: relation.user.internalId)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var friendsSection: some View {
        Section("友達") {
            if friendStore.friends.isEmpty {
                Text("まだ友達がいません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(friendStore.friends) { relation in
                HStack {
                    userRowLabel(relation.user)
                    Spacer()
                    Toggle("見せない",
                           isOn: hideFromMeBinding(store: friendStore,
                                                   internalId: relation.user.internalId))
                        .font(.caption)
                        .fixedSize()
                }
            }
        }
    }

    /// 友達の行のラベル：犬種アイコン＋名前＋表示ID。
    /// アイコンの解決は地図・設定と同じ（未設定・未制作はミックスに寄せる）。
    private func userRowLabel(_ user: AppUser) -> some View {
        HStack(spacing: 10) {
            BreedIconView(asset: breedStore.markerIconAsset(breedId: user.breedId,
                                                             colorId: user.dogColorId),
                          size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(friendDisplayName(user))
                Text(user.publicId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - QRコード生成

/// CoreImage で QR コードを実際に生成する（外部ライブラリなし）
enum QRCodeRenderer {
    static func image(from string: String, scale: CGFloat = 12) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 自分の表示IDの QR コード
struct MyQRView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = QRCodeRenderer.image(from: friendStore.me.publicId) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                }
                Text(friendStore.me.publicId)
                    .font(.title3.bold())
                    .textSelection(.enabled)
                Text("相手にこのQRを読んでもらうか、IDを入力してもらうと友達追加できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("自分のQR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

/// QR／コードで友達追加
/// 読み取り側：このモック版にはカメラ読み取りは入っていないため、コード手入力で追加する。
/// 仮想ユーザーのIDを一覧で見せるので、手入力の流れがそのまま動作確認できる。
struct QRAddView: View {
    @Environment(FriendStore.self) private var friendStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("自分のQR") {
                    HStack(spacing: 16) {
                        if let image = QRCodeRenderer.image(from: friendStore.me.publicId) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                        }
                        Text(friendStore.me.publicId)
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                }
                Section("コードで追加") {
                    TextField("相手のID（例：wan-sora31）", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("追加") { addFromCode() }
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("仮想の相手（動作確認用）") {
                    ForEach(FriendStore.mockDirectory) { user in
                        Button { code = user.publicId } label: {
                            HStack {
                                Text("🐶 \(friendDisplayName(user))")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(user.publicId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("カメラでのQR読み取りはこのモック版には入っていません。コード入力で追加できます（実カメラ対応はアプリ版のカメラ環境が整ってから）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QRで追加")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func addFromCode() {
        switch friendStore.add(byCode: code) {
        case .added(let user):
            message = "\(friendDisplayName(user)) さんを追加しました"
            code = ""
        case .alreadyFriends(let user):
            message = "\(friendDisplayName(user)) さんとはすでに友達です"
        case .notFound:
            message = "そのIDの相手は見つかりませんでした"
        }
    }
}

#Preview {
    FriendsView()
        .environment(FriendStore.preview)
        .environment(BreedStore())
}
