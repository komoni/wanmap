import Foundation

/// 共有シート（Share Extension）から受け取ったテキストを、アプリ本体へ渡すための受け渡し場所。
///
/// 設計（フェーズJ）：
/// - 拡張側はテキストをここに「保留中の取り込み」として置くだけ。
///   下書き生成（StoryTextParser）も予定の保存も、すべて本体側の責務（拡張では一切しない）。
/// - 本体は起動時とフォアグラウンド復帰時にここを見て、保留があれば取り込み画面を開く。
///   開いた時点で保留は消す（同じ文面が何度も開かないように）。
/// - 受け渡しは App Groups の共有 UserDefaults 経由。生の位置情報などは絶対に置かない
///   （置くのはユーザーが自分で共有操作したテキストだけ）。
enum SharedImportInbox {
    /// 両ターゲットで共通の App Group ID（project.yml の entitlements で宣言）
    static let appGroupID = "group.jp.wanmap.app"

    private static let textKey = "pendingImport.text"
    private static let receivedAtKey = "pendingImport.receivedAt"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// 拡張側：共有されたテキストを保留として置く
    static func save(text: String, receivedAt: Date = Date()) {
        guard let defaults else { return }
        defaults.set(text, forKey: textKey)
        defaults.set(receivedAt, forKey: receivedAtKey)
    }

    /// 本体側：保留中のテキストがあれば返す（空文字・未保存は nil）
    static func pendingText() -> String? {
        guard let text = defaults?.string(forKey: textKey),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// 本体側：取り込み画面に渡し終えたら保留を消す
    static func clear() {
        defaults?.removeObject(forKey: textKey)
        defaults?.removeObject(forKey: receivedAtKey)
    }
}
