import SwiftUI

/// ストーリー／投稿テキストの貼り付け取り込み画面
///
/// 仕様（決定済み・最重要）：
/// - Instagramの自動巡回はしない。ユーザーが自分で見つけた文面を持ち込む機能。
/// - 抽出結果は絶対に自動保存しない。下書き（StoryTextDraft）として提示し、
///   候補をタップして予定フォームで確認・保存した時に初めて予定になる。
/// - 下書きは画面内の一時データで、どこにも永続化しない（破棄＝配列から消すだけ）。
struct StoryImportView: View {
    @Environment(FacilityStore.self) private var facilityStore
    @Environment(UserPlaceStore.self) private var userPlaceStore
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss

    @State private var sourceText = ""
    @State private var baseDate = Date()
    @State private var drafts: [StoryTextDraft] = []
    @State private var formDraft: StoryTextDraft?
    /// フォームを開いた下書きのID（onDismiss 時点では formDraft が nil になり得るため別に保持）
    @State private var openedDraftID: UUID?

    var body: some View {
        NavigationStack {
            List {
                inputSection
                if !drafts.isEmpty {
                    draftsSection
                }
            }
            .navigationTitle("テキストから取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $formDraft, onDismiss: removeFormDraft) {
                PlanFormView(editing: nil,
                             defaultDate: $0.date,
                             defaultDogName: planStore.lastDogName,
                             initialTimeBand: $0.timeBand,
                             initialFacility: $0.facility,
                             initialUserPlace: $0.userPlace)
            }
        }
    }

    private var inputSection: some View {
        Section {
            TextEditor(text: $sourceText)
                .frame(minHeight: 120)
            DatePicker(selection: $baseDate, displayedComponents: .date) {
                Label("投稿日", systemImage: "calendar")
            }
            Button {
                drafts = StoryTextParser.parse(text: sourceText,
                                               baseDate: baseDate,
                                               facilities: facilityStore.facilities,
                                               userPlaces: userPlaceStore.places)
            } label: {
                HStack {
                    Spacer()
                    Label("下書きを作る", systemImage: "doc.text.magnifyingglass").bold()
                    Spacer()
                }
            }
            .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Label("文面を貼り付け", systemImage: "doc.on.clipboard")
        } footer: {
            Text("ストーリーや投稿の文面を貼ると、場所・日付・時間帯の下書きを作ります。")
                + Text("自動では保存されません。下書きを確認して保存してください。")
        }
    }

    private var draftsSection: some View {
        Section {
            ForEach(drafts) { draft in
                Button {
                    openedDraftID = draft.id
                    formDraft = draft
                } label: {
                    draftRow(draft)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        drafts.removeAll { $0.id == draft.id }
                    } label: {
                        Label("破棄", systemImage: "trash")
                    }
                }
            }
        } header: {
            Label("下書き", systemImage: "note.text")
        } footer: {
            Text("タップすると予定フォームが開きます。保存するまで予定にはなりません。")
        }
    }

    private func draftRow(_ draft: StoryTextDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(draft.placeName.isEmpty ? Color.secondary : Color.orange)
                Text(draft.placeName.isEmpty ? "場所未定" : draft.placeName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("推測：\(draft.confidence.rawValue)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            Text("\(Self.dateLabel(draft.date)) ・ \(draft.timeBand.rawValue)")
                .font(.caption)
            ForEach(draft.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// フォームを閉じたら、その下書きは一覧から外す
    /// （保存済みなら二重保存を防ぐため。キャンセルした場合も、文面から作り直せる）
    private func removeFormDraft() {
        guard let id = openedDraftID else { return }
        drafts.removeAll { $0.id == id }
        openedDraftID = nil
    }

    private static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（EEE）"
        return f.string(from: date)
    }
}

#if DEBUG
#Preview {
    StoryImportView()
        .environment(FacilityStore())
        .environment(UserPlaceStore())
        .environment(PlanStore(samplePlans: SeedData.samplePlans()))
}
#endif
