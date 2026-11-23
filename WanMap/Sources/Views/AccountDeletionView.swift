import AuthenticationServices
import SwiftUI

/// アカウント削除の画面（単位2-7）。設定から開く通常の導線と、
/// 削除の再開（サインイン直後に RootView が通常画面の上へ差し込む）の
/// 両方で使う。再開モード（isResumeGate）では、削除を終えるまで
/// 他の画面へ進ませない。
struct AccountDeletionView: View {
    @Environment(AuthService.self) private var authService
    @State private var service = AccountDeletionService()
    @State private var showConfirm = false
    var isResumeGate = false

    var body: some View {
        Form {
            if !authService.isSignedIn {
                Section {
                    Text("アカウントの削除には、Apple IDでのサインインが必要です（設定の「アカウント」からできます）。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("deletionSignInNotice")
                }
            } else {
                switch service.phase {
                case .done:
                    doneSection
                case .working:
                    workingSection
                case .needsReauthentication:
                    reauthSection
                case .idle, .failed:
                    confirmSections
                }
            }
        }
        .navigationTitle(isResumeGate ? "アカウント削除の続き" : "アカウントを削除")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 確認（開始前・失敗後の再試行）

    @ViewBuilder
    private var confirmSections: some View {
        if isResumeGate {
            Section {
                Text("前回のアカウント削除が途中で終わっています。続きを行います。")
                    .font(.callout)
                    .accessibilityIdentifier("deletionResumeNotice")
            }
        }
        Section {
            Text("サーバーに保存された、あなたの次の情報が削除されます。")
                .font(.callout)
            Text("・プロフィールと表示ID\n・登録した予定と「今ここ」\n・友達関係と友達申請\n・見せない／ブロックの設定")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("端末内に保存された情報（この端末の予定など）は残ります。送信済みのご意見・ご要望は、この操作では削除されません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("削除されるもの")
        }
        Section {
            Button(role: .destructive) {
                showConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text(isResumeGate ? "削除の続きを実行する" : "アカウントを削除する")
                    Spacer()
                }
            }
            .accessibilityIdentifier("deleteAccountStartButton")
            if service.phase == .failed {
                Text(service.statusText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("deletionErrorText")
            }
        }
        .confirmationDialog("本当に削除しますか？",
                            isPresented: $showConfirm,
                            titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                Task { await startDeletion() }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
    }

    // MARK: - 実行中

    private var workingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text(service.statusText)
                    .font(.callout)
            }
            .accessibilityIdentifier("deletionStatusText")
        }
    }

    // MARK: - 再認証

    private var reauthSection: some View {
        Section {
            Text(service.statusText)
                .font(.callout)
                .accessibilityIdentifier("deletionReauthNotice")
            SignInWithAppleButton(.signIn) { request in
                authService.configureAppleRequest(request)
            } onCompletion: { result in
                Task {
                    if await authService.reauthenticateApple(result) {
                        await service.finishAfterReauthentication()
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .accessibilityIdentifier("deletionReauthButton")
        }
    }

    // MARK: - 完了

    private var doneSection: some View {
        Section {
            Label("削除が完了しました", systemImage: "checkmark.circle.fill")
                .foregroundStyle(WanStyle.coral)
                .accessibilityIdentifier("deletionDoneMessage")
            Text("サーバー上のアカウント情報は削除されました。アプリはサインインしていない状態に戻ります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func startDeletion() async {
        guard let uid = authService.uid else { return }
        await service.run(uid: uid, displayId: authService.displayId)
    }
}
