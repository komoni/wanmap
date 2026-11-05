import SwiftUI

/// その日の予定一覧シート（カレンダーの日タップで開く）
/// ここから予定の追加・編集・削除ができる。
/// 「今ここ」は地図側で管理するものなので、ここでは表示と削除だけ（編集フォームは開かない）。
struct DayPlansView: View {
    @Environment(PlanStore.self) private var planStore

    let day: Date

    @State private var editingPlan: Plan?
    @State private var showNewForm = false

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
                }
                .onDelete { offsets in
                    offsets.map { plans[$0] }.forEach { planStore.remove($0) }
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
            .sheet(item: $editingPlan) { plan in
                PlanFormView(editing: plan, defaultDate: day, defaultDogName: planStore.lastDogName)
            }
            .sheet(isPresented: $showNewForm) {
                PlanFormView(editing: nil, defaultDate: day, defaultDogName: planStore.lastDogName)
            }
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
