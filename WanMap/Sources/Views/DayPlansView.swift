import SwiftUI

/// その日の予定一覧シート（カレンダーの日タップで開く）
/// ここから予定の追加・編集・削除ができる。
/// 「今ここ」は地図側で管理するものなので、ここでは表示と削除だけ（編集フォームは開かない）。
struct DayPlansView: View {
    @Environment(PlanStore.self) private var planStore

    let day: Date

    @State private var editingPlan: Plan?
    @State private var showNewForm = false
    /// 削除範囲ダイアログの対象（シリーズの子をスワイプ削除する時だけ使う）
    @State private var deletionTarget: Plan?
    /// 削除範囲ダイアログの表示状態（対象とは分離して管理する。F1）
    @State private var showDeletionDialog = false
    /// 削除の保存に失敗した時の表示（失敗を成功として見せない）
    @State private var showDeleteFailure = false

    private var plans: [Plan] { planStore.plans(on: day) }

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        return f.string(from: day)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    row(for: plan)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !plan.isPresence { editingPlan = plan }
                        }
                        // 行の削除は .onDelete でなく .swipeActions 経由にする。
                        // .onDelete は List 側にスワイプ削除の内部状態が残ったまま、
                        // 範囲ダイアログ確定後にストア側で行が消えると行数が合わず
                        // アプリが落ちる事象があったため（CI #40 の切り分け）。
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(plan)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewForm = true } label: { Image(systemName: "plus") }
                        // アイコンのみのボタンはUIテストから確実に押せるよう識別子を付ける（見た目・挙動は不変）
                        .accessibilityIdentifier("dayPlansAddButton")
                }
            }
            .alert("削除できませんでした", isPresented: $showDeleteFailure) {
                Button("OK") {}
            } message: {
                Text("保存に失敗したため、削除は取り消されました。")
            }
            .sheet(item: $editingPlan) { plan in
                PlanFormView(editing: plan, defaultDate: day, defaultDogName: planStore.lastDogName)
            }
            .sheet(isPresented: $showNewForm) {
                PlanFormView(editing: nil, defaultDate: day, defaultDogName: planStore.lastDogName)
            }
        }
        // 削除範囲ダイアログは、削除で消える行を含む List ではなく
        // NavigationStack（安定したホスト）に付ける（F1）
        .seriesDeletionDialog(target: $deletionTarget, isPresented: $showDeletionDialog,
                              store: planStore,
                              onFailure: { showDeleteFailure = true })
    }

    /// スワイプ削除の振る舞い：繰り返しの回は、範囲（この回だけ／シリーズ全体）を
    /// 選んでから消す（フォーム内削除と共通のダイアログを使う）。
    /// それ以外はその場で削除し、保存に失敗したら成功として見せずアラートを出す。
    private func delete(_ plan: Plan) {
        if plan.seriesID != nil {
            // 対象を先に入れてから表示する（ダイアログ側はこの順序を前提とする）
            deletionTarget = plan
            showDeletionDialog = true
        } else if !planStore.remove(plan) {
            showDeleteFailure = true
        }
    }

    private func row(for plan: Plan) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(WanStyle.lavender.opacity(0.55)).frame(width: 34, height: 34)
                if plan.isPresence {
                    Image(systemName: "person.fill").foregroundStyle(WanStyle.coral)
                } else {
                    Text("🐶")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plan.placeName.isEmpty ? "今ここ" : plan.placeName)
                        .font(.headline)
                        .lineLimit(1)
                    if plan.isEvent {
                        Text("募集")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WanStyle.apricot.opacity(0.45))
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle(for: plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for plan: Plan) -> String {
        var parts = [plan.timeBand.rawValue, plan.level.rawValue]
        if let dog = plan.dogName, !dog.isEmpty { parts.append(dog) }
        if let deadline = plan.eventDeadline {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "M/d"
            parts.append("締切 \(f.string(from: deadline))")
        }
        return parts.joined(separator: "・")
    }
}
