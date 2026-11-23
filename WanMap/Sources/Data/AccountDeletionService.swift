import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

/// アカウント削除（フェーズ2単位2-7、設計 v0.3 の端末主導削除）。
/// 進め方：状態旗（deletionJobs/{uid}）→ users の deleting 旗 →
/// 本人分のカスケード削除 → Auth ユーザーの削除。
/// どの段も再実行して安全（冪等）で、途中で終わっても次回サインイン時に
/// AuthService が状態旗を見て再開画面へ誘導する。
/// feedback（送信済みのご意見）はクライアントからは消せないため対象外で、
/// 削除画面でもその旨を明記する（「完全削除」とは言わない）。
@MainActor
@Observable
final class AccountDeletionService {

    enum Phase: Equatable {
        case idle
        case working
        case needsReauthentication
        case done
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var statusText = ""

    private var db: Firestore { Firestore.firestore() }

    /// 削除の本体。最後の Auth ユーザー削除で再認証が要る場合は
    /// phase = .needsReauthentication で戻る（再認証後に
    /// finishAfterReauthentication を呼ぶ）。
    func run(uid: String, displayId: String?) async {
        phase = .working
        do {
            statusText = "削除の準備をしています"
            try await db.collection("deletionJobs").document(uid)
                .setData(["startedAt": FieldValue.serverTimestamp()])
            let userRef = db.collection("users").document(uid)
            let userSnap = try await userRef.getDocument()
            // 再開時は AuthService が表示IDを持たないため、文書側から拾う
            let resolvedDisplayId = displayId
                ?? (userSnap.data()?["displayId"] as? String)
            if userSnap.exists {
                try await userRef.updateData(["deleting": true])
            }

            statusText = "予定と「今ここ」を削除しています"
            try await deleteDocuments(
                db.collection("plans").whereField("ownerUid", isEqualTo: uid))
            try await db.collection("presence").document(uid).delete()

            statusText = "友達関係と申請を削除しています"
            try await deleteDocuments(
                db.collection("friendships").whereField("members", arrayContains: uid))
            try await deleteDocuments(
                db.collection("friendRequests").whereField("fromUid", isEqualTo: uid))
            try await deleteDocuments(
                db.collection("friendRequests").whereField("toUid", isEqualTo: uid))
            try await deleteDocuments(
                db.collection("hiddenFrom").document(uid).collection("targets"))
            try await deleteDocuments(
                db.collection("blocks").document(uid).collection("targets"))

            statusText = "プロフィールを削除しています"
            if let resolvedDisplayId {
                try await db.collection("displayIds").document(resolvedDisplayId).delete()
            }
            if userSnap.exists {
                try await userRef.delete()
            }
        } catch {
            phase = .failed
            statusText = "削除の途中で通信エラーが発生しました。もう一度お試しください（途中までの削除は保持され、続きから再開できます）"
            return
        }
        await deleteAuthUser()
    }

    /// 再認証の後に、Auth ユーザーの削除だけをやり直す。
    func finishAfterReauthentication() async {
        phase = .working
        statusText = "アカウントを削除しています"
        await deleteAuthUser()
    }

    private func deleteAuthUser() async {
        guard let user = Auth.auth().currentUser else {
            phase = .done
            return
        }
        do {
            try await user.delete()
            phase = .done
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                phase = .needsReauthentication
                statusText = "本人確認のため、もう一度 Apple ID でサインインしてください"
            } else {
                phase = .failed
                statusText = "アカウント本体の削除に失敗しました。もう一度お試しください"
            }
        }
    }

    /// クエリに当たるドキュメントをまとめて消す（バッチ上限を避けて分割）。
    private func deleteDocuments(_ query: Query) async throws {
        let snapshot = try await query.getDocuments()
        for chunk in snapshot.documents.chunked(into: 400) {
            let batch = db.batch()
            chunk.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
