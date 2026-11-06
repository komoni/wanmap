import SwiftUI

/// 繰り返し予定の削除範囲を確認するダイアログ（共通ヘルパー）
///
/// フォーム内削除と日別一覧のスワイプ削除で、範囲選択の文言と動作が
/// 経路によって変わらないよう、ここに一本化する。
/// 対象（target）が nil でない間だけ表示され、選択かキャンセルで nil に戻る。
struct SeriesDeletionDialog: ViewModifier {
    @Binding var target: Plan?
    let store: PlanStore
    var onDeleted: () -> Void = {}
    /// 保存に失敗して削除できなかった時に呼ばれる（成功として見せないため）
    var onFailure: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "この予定は繰り返しの一部です",
            isPresented: isPresented,
            titleVisibility: .visible,
            presenting: target
        ) { plan in
            Button("この回だけ削除", role: .destructive) {
                let succeeded = store.removeOccurrence(plan)
                target = nil
                if succeeded { onDeleted() } else { onFailure() }
            }
            Button("シリーズ全体を削除", role: .destructive) {
                let succeeded = store.removeSeries(of: plan)
                target = nil
                if succeeded { onDeleted() } else { onFailure() }
            }
            Button("キャンセル", role: .cancel) {
                target = nil
            }
        } message: { _ in
            Text("削除する範囲を選んでください。削除した回は元に戻せません。")
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }
}

extension View {
    /// 繰り返し予定の削除範囲ダイアログを取り付ける
    func seriesDeletionDialog(target: Binding<Plan?>, store: PlanStore,
                              onDeleted: @escaping () -> Void = {},
                              onFailure: @escaping () -> Void = {}) -> some View {
        modifier(SeriesDeletionDialog(target: target, store: store,
                                      onDeleted: onDeleted, onFailure: onFailure))
    }
}
