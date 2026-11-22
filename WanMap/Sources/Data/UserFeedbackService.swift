import FirebaseFirestore
import Foundation
import UIKit

/// ご意見・ご要望の送信役（単位2-6、設計 v0.3 の feedback/{id}）。
/// 要望・不具合・通報の共通受け口へ create だけを行う。読み戻しは
/// アプリからは行わない（ルールでもクライアントの読み取りは不可。
/// 内容の確認はコンソール側）。
/// 端末情報は本人がフォームで同意した時だけ添える。
@MainActor
@Observable
final class UserFeedbackService {

    /// 送信の種類。rawValue はサーバー側の type と一致させる
    enum Kind: String, CaseIterable, Identifiable {
        case request
        case bug
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .request: return "要望"
            case .bug: return "不具合"
            case .other: return "その他"
            }
        }
    }

    private(set) var isSending = false

    /// 本文の正規化：前後の空白・改行を除き、1〜2000文字の時だけ値を返す
    nonisolated static func normalizedBody(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return nil }
        return trimmed
    }

    /// 端末情報（本人が同意した時だけ payload に添える）
    static func deviceInfo() -> [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "不明"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "不明"
        return [
            "appVersion": "\(version) (\(build))",
            "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "model": UIDevice.current.model,
        ]
    }

    /// 送信する。成功した時だけ true（失敗を成功として見せない）
    func submit(uid: String, kind: Kind, body: String, attachDeviceInfo: Bool) async -> Bool {
        guard let normalized = Self.normalizedBody(body), !isSending else { return false }
        isSending = true
        defer { isSending = false }
        var data: [String: Any] = [
            "uid": uid,
            "type": kind.rawValue,
            "body": normalized,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if attachDeviceInfo {
            data["device"] = Self.deviceInfo()
        }
        do {
            _ = try await Firestore.firestore()
                .collection("feedback")
                .addDocument(data: data)
            return true
        } catch {
            return false
        }
    }
}
