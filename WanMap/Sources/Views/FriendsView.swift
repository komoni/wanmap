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
    @Environment(AuthService.self) private var authService
    @Environment(FriendService.self) private var friendService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showMyQR = false
    @State private var showQRAdd = false
    @State private var message: String?
    /// サーバー検索の状態（サインイン中だけ使う）
    @State private var serverSearch: ServerSearchState = .idle

    private enum ServerSearchState: Equatable {
        case idle
        case searching
        case found(uid: String, displayId: String)
        case notFound
        case isSelf
    }

    private var serverMode: Bool { friendStore.serverDriven }

    var body: some View {
        NavigationStack {
            List {
                myIdSection
                searchSection
                if !friendStore.incomingRequests.isEmpty {
                    incomingSection
                }
                if serverMode {
                    outgoingSection
                }
                friendsSection
                Section {
                    Text(serverMode
                         ? "友達機能はサーバーと連携しています。申請や承認は実際に相手へ届きます。位置と予定の共有は次の段階で有効になります。"
                         : "友達機能はまだモックです。申請や承認はこの端末の中だけで処理され、実際に相手へは届きません。設定のアカウントからサインインすると、実際の友達とつながれます。位置と予定が見えるのは、友達のうち共有に同意した相手だけです（全員には見えません）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("友達")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQRAdd = true } label: {
                        Image(systemName: "qrcode")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showMyQR) { MyQRView() }
            .sheet(isPresented: $showQRAdd) { QRAddView() }
        }
    }

    /// 友達に渡すID。サインイン中はサーバー表示ID（検索で実際に引ける方）、
    /// 未サインインでは端末内のモックID。
    private var shareableId: String {
        authService.displayId ?? friendStore.me.publicId
    }

    /// 自分のIDをタッチでコピーした直後の表示
    @State private var copiedMyId = false

    private func copyMyId() {
        UIPasteboard.general.string = shareableId
        copiedMyId = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedMyId = false
        }
    }

    private var myIdSection: some View {
        Section("自分のID") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shareableId)
                        .font(.title2.bold())
                        .onTapGesture { copyMyId() }
                    Button { copyMyId() } label: {
                        Image(systemName: copiedMyId ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("IDをコピー")
                }
                if copiedMyId {
                    Text("コピーしました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if authService.displayId != nil {
                    Text("サーバー表示ID（友達検索で使われるID）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("内部ID \(friendStore.me.internalId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("このIDやQRコードを友達に送ると、アプリで友達になれます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { showMyQR = true } label: {
                Label("QRコードを表示", systemImage: "qrcode")
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if serverMode {
            serverSearchSection
        } else {
            localSearchSection
        }
    }

    /// サインイン中：表示IDの完全一致でサーバーから探す
    private var serverSearchSection: some View {
        Section("友達を探す") {
            HStack {
                TextField("相手の表示ID（wan-xxxxxx）", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("探す") {
                    serverSearch = .searching
                    let code = searchText
                    Task {
                        switch await friendService.lookup(displayId: code) {
                        case .found(let uid):
                            serverSearch = .found(uid: uid,
                                                  displayId: FriendService.normalizeCode(code))
                        case .notFound:
                            serverSearch = .notFound
                        case .isSelf:
                            serverSearch = .isSelf
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                          || serverSearch == .searching)
            }
            switch serverSearch {
            case .idle:
                EmptyView()
            case .searching:
                Text("探しています…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notFound:
                Text("その表示IDの相手は見つかりませんでした")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .isSelf:
                Text("それは自分の表示IDです")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .found(let uid, let displayId):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayId)
                        Text("このIDの相手が見つかりました")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if friendStore.friends.contains(where: { $0.user.internalId == uid }) {
                        Text("友達です")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if friendStore.relations.contains(where: {
                        $0.user.internalId == uid && $0.state == .outgoing
                    }) {
                        Text("申請中です")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if friendStore.incomingRequests.contains(where: {
                        $0.user.internalId == uid
                    }) {
                        Text("相手から申請が届いています")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("申請") {
                            Task {
                                await friendService.sendRequest(toUid: uid, displayId: displayId)
                                if friendService.errorMessage == nil {
                                    message = "申請を送りました"
                                    serverSearch = .idle
                                    searchText = ""
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            if let error = friendService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 未サインイン：端末内モックの検索（従来動作）
    private var localSearchSection: some View {
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

    /// 申請中（サーバー連携中だけ表示）
    private var outgoingSection: some View {
        Section("申請中") {
            let outgoing = friendStore.relations.filter { $0.state == .outgoing }
            if outgoing.isEmpty {
                Text("申請中の相手はいません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(outgoing) { relation in
                HStack {
                    userRowLabel(relation.user)
                    Spacer()
                    Button("取り消す", role: .destructive) {
                        Task { await friendService.cancelOutgoing(toUid: relation.user.internalId) }
                    }
                    .buttonStyle(.bordered)
                }
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
                        if serverMode {
                            Task {
                                await friendService.approve(fromUid: relation.user.internalId)
                                if friendService.errorMessage == nil {
                                    message = "\(friendDisplayName(relation.user)) さんと友達になりました"
                                }
                            }
                        } else {
                            friendStore.approve(internalId: relation.user.internalId)
                            message = "\(friendDisplayName(relation.user)) さんと友達になりました"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("断る", role: .destructive) {
                        if serverMode {
                            Task { await friendService.reject(fromUid: relation.user.internalId) }
                        } else {
                            friendStore.reject(internalId: relation.user.internalId)
                        }
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
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    /// サインイン中はサーバー表示ID（検索で実際に引ける方）を出す
    private var effectiveId: String { authService.displayId ?? friendStore.me.publicId }

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = QRCodeRenderer.image(from: effectiveId) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                }
                Text(effectiveId)
                    .font(.title3.bold())
                    .onTapGesture {
                        UIPasteboard.general.string = effectiveId
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                if copied {
                    Text("コピーしました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var message: String?

    /// サインイン中はサーバー表示ID（検索で実際に引ける方）を出す
    private var effectiveId: String { authService.displayId ?? friendStore.me.publicId }

    var body: some View {
        NavigationStack {
            List {
                Section("自分のQR") {
                    HStack(spacing: 16) {
                        if let image = QRCodeRenderer.image(from: effectiveId) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 88, height: 88)
                        }
                        Text(effectiveId)
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                }
                if friendStore.serverDriven {
                    Section {
                        Text("サインイン中は、コードでの追加は友達画面の「友達を探す」から表示IDで申請する形になります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
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
        .environment(AuthService())
        .environment(FriendService())
}
