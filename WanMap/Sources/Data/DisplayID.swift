import Foundation

/// サーバー表示ID（wan-xxxxxx）の生成と検証（設計 v0.1 の決定）。
/// 友達検索の鍵になる公開IDで、Firestore の displayIds コレクションで
/// 一意を担保する（採番の実行は AuthService）。
/// 読み間違えやすい文字（0・1・i・l・o）は字面から外してある。
/// ルール側の形式検証（firestore.rules の正規表現）と字面を揃えること。
enum DisplayID {
    static let prefix = "wan-"
    static let bodyLength = 6
    /// 使用する文字（小文字22字＋数字8字＝30字）
    static let alphabet = "abcdefghjkmnpqrstuvwxyz23456789"

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    static func generate<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let chars = Array(alphabet)
        var body = ""
        body.reserveCapacity(bodyLength)
        for _ in 0..<bodyLength {
            body.append(chars[Int.random(in: 0..<chars.count, using: &rng)])
        }
        return prefix + body
    }

    static func isValid(_ value: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let body = value.dropFirst(prefix.count)
        guard body.count == bodyLength else { return false }
        return body.allSatisfy { alphabet.contains($0) }
    }
}
