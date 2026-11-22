import SwiftUI

/// ご意見・ご要望フォーム（単位2-6）。設定画面から開く。
/// 送信先はサーバーの feedback（要望・不具合の共通受け口）。
/// 誰からの意見か分かるよう、送信にはサインインが要る。
struct FeedbackFormView: View {
    @Environment(AuthService.self) private var authService
    @State private var service = UserFeedbackService()
    @State private var kind: UserFeedbackService.Kind = .request
    @State private var bodyText = ""
    @State private var attachDeviceInfo = false
    @State private var sent = false
    @State private var failed = false

    var body: some View {
        Form {
            if !authService.isSignedIn {
                Section {
                    Text("要望・不具合の送信には、Apple IDでのサインインが必要です（設定の「アカウント」からできます）。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("feedbackSignInNotice")
                }
            } else if sent {
                Section {
                    Label("送信しました。ありがとうございます。", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(WanStyle.coral)
                        .accessibilityIdentifier("feedbackSentMessage")
                    Text("内容は開発側で確認します。アプリ内での返信は行いません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("種類") {
                    Picker("種類", selection: $kind) {
                        ForEach(UserFeedbackService.Kind.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("feedbackKindPicker")
                }

                Section("内容") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("feedbackBodyEditor")
                    Text("\(bodyText.count) / 2000")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("端末情報を添える", isOn: $attachDeviceInfo)
                        .accessibilityIdentifier("feedbackDeviceToggle")
                } footer: {
                    Text("不具合の報告では、機種やOSの情報があると原因を追いやすくなります。添えるかどうかは選べます。")
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if service.isSending {
                                ProgressView()
                            }
                            Text(service.isSending ? "送信中…" : "送信する")
                            Spacer()
                        }
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedbackSubmitButton")
                    if failed {
                        Text("送信できませんでした。通信状態を確認して、もう一度お試しください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("ご意見・ご要望")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSend: Bool {
        !service.isSending && UserFeedbackService.normalizedBody(bodyText) != nil
    }

    private func submit() async {
        guard let uid = authService.uid else { return }
        failed = false
        let ok = await service.submit(uid: uid, kind: kind, body: bodyText,
                                      attachDeviceInfo: attachDeviceInfo)
        if ok {
            sent = true
            bodyText = ""
        } else {
            failed = true
        }
    }
}
