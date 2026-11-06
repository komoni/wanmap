import SwiftUI

/// 繰り返し予定の削除範囲を確認するダイアログ（共通ヘルパー）
///
/// フォーム内削除と日別一覧のスワイプ削除で、範囲選択の文言と動作が
/// 経路によって変わらないよう、ここに一本化する。
///
/// 表示状態（isPresented）と削除対象（target）は分離している（F1）：
/// - 表示は独立した Bool で制御する。呼び出し側は先に target へ対象を入れてから
///   isPresented を true にする。
/// - 確定時は、対象をローカルに確保してストア操作を1回だけ行う。
///   閉じる処理と target の破棄は連動させない
///   （target は次の削除要求で置き換わるまで残る）。
///   以前は target の nil 化と表示状態を算出 Binding で連動させていて、
///   削除確定と同時に表示対象そのものが消える構造だった（test08 で削除後に
///   アプリが終了する事象の切り分け対応）。
/// - 破壊アクション内では isPresented を明示的に書き換えない（E2）。
///   閉じる動作は confirmationDialog の標準動作（アクション実行後に自動で
///   閉じ、isPresented へ false が書き戻される）に任せる。確定アクション内で
///   「表示 Bool の書き込み＋ストア書き込み」という2つの更新が重なると、
///   List の差分更新に同じ削除差分が二重に適用される形の件数不整合
///   （test08 のクラッシュ）が起きるため、その発生源を取り除く。
struct SeriesDeletionDialog: ViewModifier {
    /// 削除対象の控え（payload）。表示制御とは連動させない
    @Binding var target: Plan?
    /// 表示状態（target とは独立した Bool）
    @Binding var isPresented: Bool
    let store: PlanStore
    var onDeleted: () -> Void = {}
    /// 保存に失敗して削除できなかった時に呼ばれる（成功として見せないため）
    var onFailure: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "この予定は繰り返しの一部です",
            isPresented: $isPresented,
            titleVisibility: .visible,
            presenting: target
        ) { plan in
            Button("この回だけ削除", role: .destructive) {
                // 対象はアクションの引数（表示時点の控え）として確保し、
                // ストア操作を1回だけ行う。ダイアログは標準動作で自動的に
                // 閉じるため、ここでは isPresented を書き換えない（E2）。
                // target はここでは nil にしない（次の削除要求で置き換わる）。
                let targetPlan = plan
                if store.removeOccurrence(targetPlan) { onDeleted() } else { onFailure() }
            }
            Button("シリーズ全体を削除", role: .destructive) {
                // 「この回だけ削除」と同じく、isPresented は書き換えず
                // 標準の dismiss に任せる（E2）。
                let targetPlan = plan
                if store.removeSeries(of: targetPlan) { onDeleted() } else { onFailure() }
            }
            Button("キャンセル", role: .cancel) {
                // 閉じるだけ。ストア操作はせず、target にも触らない
                isPresented = false
            }
        } message: { _ in
            Text("削除する範囲を選んでください。削除した回は元に戻せません。")
        }
    }
}

extension View {
    /// 繰り返し予定の削除範囲ダイアログを取り付ける
    func seriesDeletionDialog(target: Binding<Plan?>, isPresented: Binding<Bool>, store: PlanStore,
                              onDeleted: @escaping () -> Void = {},
                              onFailure: @escaping () -> Void = {}) -> some View {
        modifier(SeriesDeletionDialog(target: target, isPresented: isPresented, store: store,
                                      onDeleted: onDeleted, onFailure: onFailure))
    }
}
