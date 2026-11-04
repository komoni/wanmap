import Foundation

/// 推測の確度（推測由来の下書きだけに付ける情報。手入力の予定には付けない。決定済み仕様）
/// 上限は「中」。根拠が弱いものは「低」にする。
enum InferenceConfidence: String, CaseIterable, Equatable {
    case medium = "中"
    case low = "低"
}

/// ストーリー／投稿テキストから起こした推測ドラフト（下書き）
///
/// 設計（決定済み・最重要）：
/// - 下書きは Plan とは別型で、PlanStore には保存されない。
///   ユーザーがフォームで確認・編集して保存した時に初めて Plan になる（自動保存は絶対にしない）。
/// - 確度・根拠は下書き側だけの情報で、保存される Plan には持ち込まない。
struct StoryTextDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    /// 一致した場所名。見つからなかった場合は空（ユーザーがフォームで入れる）
    var placeName: String
    /// 公式施設と名前が一致した場合に引き継ぐ（座標・表示名をフォームへ渡すため）
    var facility: Facility?
    /// 自分で追加した場所と名前が一致した場合に引き継ぐ（公式施設より優先）
    var userPlace: UserPlace?
    /// 対象日（startOfDay）
    var date: Date
    var timeBand: TimeBand
    var confidence: InferenceConfidence
    /// 根拠メモ（どの語から取ったかを短く。ユーザーが下書き一覧で確認する用）
    var reasons: [String]
}

/// ストーリー／投稿テキストの貼り付け取り込み用パーサー（UIから分離した純粋ロジック）
///
/// 解釈ルール（決定済み仕様）：
/// - 投稿日と実際の日付は前後しうる前提で、多少のズレはエラー扱いしない。
///   定例日（毎月第1日曜など）と合わない日付でも弾かない。
/// - 場所は登録済み施設名・自分の場所名が文面に含まれていれば候補にする（複数ヒットは全部出す）。
/// - 日付表現が取れなければ基準日（投稿日）を仮置きし、根拠メモにその旨を書く。
enum StoryTextParser {

    /// テキストと基準日（投稿日）から下書き候補を作る。
    /// 場所が1つも一致しなければ、日付・時間帯だけを拾った下書きを1件返す。
    static func parse(text: String,
                      baseDate: Date,
                      facilities: [Facility],
                      userPlaces: [UserPlace]) -> [StoryTextDraft] {
        let cal = Self.calendar
        let base = cal.startOfDay(for: baseDate)
        // 全角数字を半角にそろえた作業用テキスト（日付の数字読み取り用）
        let folded = text.folding(options: .widthInsensitive, locale: Locale(identifier: "ja_JP"))

        let dateResult = parseDate(in: folded, base: base, calendar: cal)
        let bandResult = parseTimeBand(in: folded)
        let placeMatches = matchPlaces(in: text, facilities: facilities, userPlaces: userPlaces)

        var reasons: [String] = []
        if let expression = dateResult.expression {
            reasons.append("日付：「\(expression)」から判断")
        } else {
            reasons.append("日付の表現が見つからず、投稿日を仮置きしました")
        }
        if let keyword = bandResult.keyword {
            reasons.append("時間帯：「\(keyword)」から\(bandResult.band.rawValue)")
        }

        // 確度：場所が名前で一致＋日付表現が明示的なら「中」、どちらか欠ける／曖昧なら「低」
        let confidence: InferenceConfidence =
            (!placeMatches.isEmpty && dateResult.isExplicit) ? .medium : .low

        if placeMatches.isEmpty {
            return [StoryTextDraft(
                placeName: "",
                facility: nil,
                userPlace: nil,
                date: dateResult.date,
                timeBand: bandResult.band,
                confidence: .low,
                reasons: ["場所の名前は見つかりませんでした"] + reasons
            )]
        }

        return placeMatches.map { match in
            StoryTextDraft(
                placeName: match.name,
                facility: match.facility,
                userPlace: match.userPlace,
                date: dateResult.date,
                timeBand: bandResult.band,
                confidence: confidence,
                reasons: ["場所：「\(match.name)」が文面に含まれていました"] + reasons
            )
        }
    }

    // MARK: - カレンダー

    /// 日曜始まり・日本語ロケールで固定（CalendarView と同じ流儀。端末設定でズレない）
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = 1
        return c
    }()

    private static let weekdayNumbers: [Character: Int] = [
        "日": 1, "月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7,
    ]

    // MARK: - 場所の照合

    private struct PlaceMatch {
        var name: String
        var facility: Facility?
        var userPlace: UserPlace?
        var normalizedLength: Int
    }

    /// 施設検索（FacilityStore／UserPlaceStore）と同じ正規化で、文面に場所名が含まれるかを照合する。
    /// 自分の場所を先に、次に名前の長い（＝より具体的な）一致を優先して並べる。
    private static func matchPlaces(in text: String,
                                    facilities: [Facility],
                                    userPlaces: [UserPlace]) -> [PlaceMatch] {
        let normalizedText = FacilityStore.normalize(text)
        guard !normalizedText.isEmpty else { return [] }

        var matches: [PlaceMatch] = []

        for place in userPlaces {
            let key = FacilityStore.normalize(place.name)
            guard key.count >= 2, normalizedText.contains(key) else { continue }
            matches.append(PlaceMatch(name: place.name, facility: nil,
                                      userPlace: place, normalizedLength: key.count))
        }
        for facility in facilities {
            // 正式名と表示名の両方で照合し、一施設につき候補は1件まで
            var hitName: String?
            var hitLength = 0
            for candidate in [facility.displayName, facility.name] {
                let key = FacilityStore.normalize(candidate)
                if key.count >= 2, normalizedText.contains(key), key.count > hitLength {
                    hitName = candidate
                    hitLength = key.count
                }
            }
            if let hitName {
                matches.append(PlaceMatch(name: hitName, facility: facility,
                                          userPlace: nil, normalizedLength: hitLength))
            }
        }

        return matches.sorted { a, b in
            if (a.userPlace != nil) != (b.userPlace != nil) { return a.userPlace != nil }
            return a.normalizedLength > b.normalizedLength
        }
    }

    // MARK: - 日付の解釈

    private struct DateResult {
        var date: Date
        /// 根拠になった表現（例：「明日」「11月5日」）。取れなかった場合は nil
        var expression: String?
        /// 日付表現が明示的に取れたか（確度の判定に使う）
        var isExplicit: Bool
    }

    /// 優先順：○月○日 → 明後日／明日／今日 → 来週○曜 → 今週末／週末 → 今週○曜／○曜 → 来週 → ○日
    private static func parseDate(in text: String, base: Date, calendar cal: Calendar) -> DateResult {
        let ns = text as NSString

        // ○月○日（例：11月5日）。過去日なら翌年に倒す（予定の取り込みが目的なので未来側を優先）
        if let m = firstMatch(of: #"(\d{1,2})月(\d{1,2})日"#, in: text),
           let month = Int(m.groups[0]), let day = Int(m.groups[1]) {
            let year = cal.component(.year, from: base)
            if let date = makeDate(year: year, month: month, day: day, calendar: cal) {
                if date >= base {
                    return DateResult(date: date, expression: m.text, isExplicit: true)
                }
                if let nextYear = makeDate(year: year + 1, month: month, day: day, calendar: cal) {
                    return DateResult(date: nextYear, expression: m.text, isExplicit: true)
                }
            }
        }

        // 相対日
        if ns.contains("明後日") {
            return DateResult(date: addDays(2, to: base, calendar: cal), expression: "明後日", isExplicit: true)
        }
        if ns.contains("明日") {
            return DateResult(date: addDays(1, to: base, calendar: cal), expression: "明日", isExplicit: true)
        }
        if ns.contains("今日") {
            return DateResult(date: base, expression: "今日", isExplicit: true)
        }
        if ns.contains("本日") {
            return DateResult(date: base, expression: "本日", isExplicit: true)
        }

        // 来週○曜（例：来週の日曜、来週土曜）
        if let m = firstMatch(of: #"来週の?([月火水木金土日])曜"#, in: text),
           let ch = m.groups[0].first, let target = weekdayNumbers[ch] {
            return DateResult(date: nextWeekWeekday(target, from: base, calendar: cal),
                              expression: m.text, isExplicit: true)
        }

        // 今週末／週末 → その週の土曜日（土曜当日なら当日、日曜は次の土曜）
        if ns.contains("今週末") || ns.contains("週末") {
            let weekday = cal.component(.weekday, from: base)
            let offset = (7 - weekday) % 7
            return DateResult(date: addDays(offset, to: base, calendar: cal),
                              expression: ns.contains("今週末") ? "今週末" : "週末",
                              isExplicit: true)
        }

        // 今週○曜／単独の○曜（例：今週の土曜、土曜）→ 直近のその曜日（当日含む）
        if let m = firstMatch(of: #"(?:今週の?)?([月火水木金土日])曜"#, in: text),
           let ch = m.groups[0].first, let target = weekdayNumbers[ch] {
            let weekday = cal.component(.weekday, from: base)
            let offset = (target - weekday + 7) % 7
            return DateResult(date: addDays(offset, to: base, calendar: cal),
                              expression: m.text, isExplicit: true)
        }

        // 来週（曜日なし）→ 7日後
        if ns.contains("来週") {
            return DateResult(date: addDays(7, to: base, calendar: cal), expression: "来週", isExplicit: true)
        }

        // ○日だけ（例：15日）→ 今月。その日が過ぎていれば来月
        if let m = firstMatch(of: #"(\d{1,2})日"#, in: text),
           let day = Int(m.groups[0]) {
            let comps = cal.dateComponents([.year, .month], from: base)
            if let date = makeDate(year: comps.year ?? 0, month: comps.month ?? 0, day: day, calendar: cal) {
                if date >= base {
                    return DateResult(date: date, expression: m.text, isExplicit: true)
                }
                if let next = cal.date(byAdding: .month, value: 1, to: date) {
                    return DateResult(date: next, expression: m.text, isExplicit: true)
                }
            }
        }

        // 取れない場合は基準日（投稿日）を仮置きする。エラーにはしない（決定済み仕様）
        return DateResult(date: base, expression: nil, isExplicit: false)
    }

    /// 来週○曜：直近のその曜日が「来週」に入らない場合はさらに1週間先にする
    private static func nextWeekWeekday(_ target: Int, from base: Date, calendar cal: Calendar) -> Date {
        let weekday = cal.component(.weekday, from: base)
        var offset = (target - weekday + 7) % 7
        if offset == 0 { offset = 7 }
        var candidate = addDays(offset, to: base, calendar: cal)
        let startOfNextWeek = addDays(8 - weekday, to: base, calendar: cal)
        if candidate < startOfNextWeek {
            candidate = addDays(7, to: candidate, calendar: cal)
        }
        return candidate
    }

    private static func makeDate(year: Int, month: Int, day: Int, calendar cal: Calendar) -> Date? {
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        // 2月30日などの不正な日付は date(from:) が繰り上げてしまうので、往復チェックで弾く
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard comps.year == year, comps.month == month, comps.day == day else { return nil }
        return cal.startOfDay(for: date)
    }

    private static func addDays(_ days: Int, to date: Date, calendar cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    // MARK: - 時間帯の解釈

    private struct BandResult {
        var band: TimeBand
        /// 根拠になった語。無ければ nil（＝終日）
        var keyword: String?
    }

    /// 時間帯の語は、文面で一番早く出てきたグループを採用する（夕方は「夜」に寄せる）
    private static func parseTimeBand(in text: String) -> BandResult {
        let groups: [(band: TimeBand, keywords: [String])] = [
            (.morning, ["朝", "午前", "モーニング"]),
            (.noon, ["昼", "午後", "ランチ"]),
            (.night, ["夕方", "夜", "晩", "夕"]),
        ]
        var best: (band: TimeBand, keyword: String, location: Int)?
        for group in groups {
            for keyword in group.keywords {
                guard let range = text.range(of: keyword) else { continue }
                let location = text.distance(from: text.startIndex, to: range.lowerBound)
                if best == nil || location < best!.location {
                    best = (group.band, keyword, location)
                }
            }
        }
        if let best {
            return BandResult(band: best.band, keyword: best.keyword)
        }
        return BandResult(band: .allDay, keyword: nil)
    }

    // MARK: - 正規表現ヘルパー

    private struct RegexMatch {
        var text: String
        var groups: [String]
    }

    private static func firstMatch(of pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              result.numberOfRanges >= 2
        else { return nil }
        var groups: [String] = []
        for i in 1..<result.numberOfRanges {
            if let range = Range(result.range(at: i), in: text) {
                groups.append(String(text[range]))
            } else {
                groups.append("")
            }
        }
        guard let whole = Range(result.range, in: text) else { return nil }
        return RegexMatch(text: String(text[whole]), groups: groups)
    }
}
