import Foundation

/// 日本の祝日（内閣府「国民の祝日」CSVから生成した同梱データ、2025〜2027年分）。
/// 実機フィードバック第2ラウンド（2026-11-14）でカレンダー表示用に追加した。
/// データの正本は WanMap/Resources/holidays-jp.json（yyyy-MM-dd → 祝日名、
/// 振替休日・国民の休日を含む）。2028年以降は内閣府の公表に合わせて
/// JSON を差し替えること。
enum HolidayCalendar {
    private static let table: [String: String] = {
        guard let url = Bundle.main.url(forResource: "holidays-jp", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }()

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// その日の祝日名（祝日でなければ nil）
    static func name(for date: Date) -> String? {
        table[keyFormatter.string(from: date)]
    }

    static func isHoliday(_ date: Date) -> Bool {
        name(for: date) != nil
    }
}
