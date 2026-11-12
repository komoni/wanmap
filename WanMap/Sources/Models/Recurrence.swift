import Foundation

/// アプリ全体で共用する暦（フェーズQレビュー R6）。
/// 端末の既定カレンダーがグレゴリオ暦以外の環境（和暦・仏暦など）でも
/// 「毎月同日」「毎月第○曜日」の意味が変わらないよう、グレゴリオ暦・
/// Asia/Tokyo を単一の生成箇所から配る。生成（RecurrenceGenerator）・
/// フォーム（PlanFormView）・保存（PlanStore）のすべてがこの1つを使う。
enum WanMapCalendar {
    static let shared: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }()
}

/// 繰り返しの種類（確定仕様：毎週／毎月同日／毎月第○曜日 の3種のみ）
enum RecurrenceKind: String, Codable, CaseIterable {
    case weekly
    case monthlyDay
    case monthlyOrdinalWeekday
}

/// 繰り返し規則。kind ごとに必要な項目だけを持ち、不要な項目は nil にする。
/// 曜日は Calendar の weekday と同じ数値（日曜=1 … 土曜=7）。
struct RecurrenceRule: Codable, Equatable {
    var kind: RecurrenceKind
    var weekday: Int?
    var dayOfMonth: Int?
    var ordinal: Int?

    /// フォームで選ばれた日付から、その種類の規則を導出する
    /// （毎月第○曜日の「第○」と曜日は、選択した初回日付から決まる）
    init(kind: RecurrenceKind, startDate: Date, calendar: Calendar) {
        self.kind = kind
        let weekday = calendar.component(.weekday, from: startDate)
        let day = calendar.component(.day, from: startDate)
        switch kind {
        case .weekly:
            self.weekday = weekday
            self.dayOfMonth = nil
            self.ordinal = nil
        case .monthlyDay:
            self.weekday = nil
            self.dayOfMonth = day
            self.ordinal = nil
        case .monthlyOrdinalWeekday:
            self.weekday = weekday
            self.dayOfMonth = nil
            self.ordinal = (day - 1) / 7 + 1
        }
    }

    init(kind: RecurrenceKind, weekday: Int? = nil, dayOfMonth: Int? = nil, ordinal: Int? = nil) {
        self.kind = kind
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.ordinal = ordinal
    }
}

/// シリーズの共通内容（親が保持する雛形）。
/// 日付・ID・「今ここ」情報は持たない。イベント締切も持たない
/// （締切は各回で個別に設定するものとして、今回は対象外にしている）。
struct PlanTemplate: Codable, Equatable {
    var personName: String
    var dogName: String?
    var placeName: String
    var latitude: Double?
    var longitude: Double?
    var timeBand: TimeBand
    var level: AttendanceLevel
    var isEvent: Bool
    var hidesOwnLocation: Bool

    init(personName: String, dogName: String?, placeName: String,
         latitude: Double?, longitude: Double?,
         timeBand: TimeBand, level: AttendanceLevel,
         isEvent: Bool, hidesOwnLocation: Bool) {
        self.personName = personName
        self.dogName = dogName
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.timeBand = timeBand
        self.level = level
        self.isEvent = isEvent
        self.hidesOwnLocation = hidesOwnLocation
    }

    /// 予定（雛形として組み立てた1件）から共通内容を取り出す
    init(plan: Plan) {
        self.init(personName: plan.personName, dogName: plan.dogName,
                  placeName: plan.placeName, latitude: plan.latitude, longitude: plan.longitude,
                  timeBand: plan.timeBand, level: plan.level,
                  isEvent: plan.isEvent, hidesOwnLocation: plan.hidesOwnLocation)
    }
}

/// 繰り返し予定のシリーズ（親）。子は実体化された Plan で、
/// 読み込みや表示のたびに親から再生成はしない（確定仕様）。
struct RecurrenceSeries: Codable, Identifiable, Equatable {
    var id: UUID
    var rule: RecurrenceRule
    var startDate: Date           // 初回探索の基準日
    var occurrenceCount: Int      // 初回を含む開催回数（3／6／12）
    var timeZoneID: String        // 生成時のタイムゾーン
    var template: PlanTemplate    // 共通内容
    var createdAt: Date
}

/// シリーズ予定の編集・削除の対象範囲。
/// 初期実装は「この回だけ」「シリーズ全体」の2種のみだったが、
/// 設定・カレンダーバッチ単位4（2026-11-12）で「この回以降」を追加した。
/// 「この回以降」の保存はシリーズ分割で行う（PlanStore.updateFollowing）。
enum PlanEditScope {
    case occurrence
    case following
    case series
}

/// 繰り返しの開催日を生成する純粋関数。
/// カレンダー（タイムゾーン含む）を外から渡せるようにし、暦の境界ケースを
/// 決定的にテストできるようにしてある。不正な規則・回数のときは nil を返す。
enum RecurrenceGenerator {
    /// 選べる回数（初回を含む）
    static let allowedCounts = [3, 6, 12]

    /// 開催日を開始日から count 回分生成する。生成できなければ nil。
    static func dates(rule: RecurrenceRule, start: Date, count: Int, calendar: Calendar) -> [Date]? {
        guard allowedCounts.contains(count) else { return nil }
        let startDay = calendar.startOfDay(for: start)
        let startWeekday = calendar.component(.weekday, from: startDay)
        let startDayOfMonth = calendar.component(.day, from: startDay)
        let startOrdinal = (startDayOfMonth - 1) / 7 + 1

        let result: [Date]
        switch rule.kind {
        case .weekly:
            // 開始日の曜日と一致していること（秒数加算ではなく暦で7日ずつ進める）
            guard rule.weekday == startWeekday else { return nil }
            result = (0..<count).compactMap {
                calendar.date(byAdding: .day, value: 7 * $0, to: startDay)
            }
        case .monthlyDay:
            guard let dayOfMonth = rule.dayOfMonth,
                  (1...31).contains(dayOfMonth),
                  dayOfMonth == startDayOfMonth,
                  let days = monthlyDays(dayOfMonth: dayOfMonth, startDay: startDay,
                                         count: count, calendar: calendar)
            else { return nil }
            result = days
        case .monthlyOrdinalWeekday:
            guard let weekday = rule.weekday, (1...7).contains(weekday), weekday == startWeekday,
                  let ordinal = rule.ordinal, (1...5).contains(ordinal), ordinal == startOrdinal,
                  let days = monthlyOrdinalDays(weekday: weekday, ordinal: ordinal,
                                                startDay: startDay, count: count, calendar: calendar)
            else { return nil }
            result = days
        }
        // 途中で生成に失敗した回があれば、部分的な件数を黙って返さない
        guard result.count == count else { return nil }
        return result
    }

    /// 毎月同日：毎月、元の指定日をその月へ適用する。
    /// その月に存在しない日は末日に寄せる（翌月は元の日に戻るので、ずれが蓄積しない）。
    private static func monthlyDays(dayOfMonth: Int, startDay: Date, count: Int,
                                    calendar: Calendar) -> [Date]? {
        var result: [Date] = []
        for offset in 0..<count {
            guard let monthStart = targetMonthStart(offset: offset, from: startDay, calendar: calendar),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count,
                  let day = calendar.date(byAdding: .day, value: min(dayOfMonth, daysInMonth) - 1,
                                          to: monthStart)
            else { return nil }
            result.append(day)
        }
        return result
    }

    /// 毎月第○曜日：第○曜日がその月に存在しない場合（第5曜日だけが起こりうる）は、
    /// その月の最後の同じ曜日へ倒す（Web版プロトタイプの実証済み挙動に合わせる）。
    private static func monthlyOrdinalDays(weekday: Int, ordinal: Int, startDay: Date,
                                           count: Int, calendar: Calendar) -> [Date]? {
        var result: [Date] = []
        for offset in 0..<count {
            guard let monthStart = targetMonthStart(offset: offset, from: startDay, calendar: calendar)
            else { return nil }
            let firstWeekday = calendar.component(.weekday, from: monthStart)
            let toFirstMatch = (weekday - firstWeekday + 7) % 7
            guard let firstMatch = calendar.date(byAdding: .day, value: toFirstMatch, to: monthStart),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
            else { return nil }
            // その月の該当曜日は最低4回ある。第○が件数を超えたら最後の1回を使う。
            let matchCount = (daysInMonth - 1 - toFirstMatch) / 7 + 1
            let chosenIndex = min(ordinal, matchCount)
            guard let day = calendar.date(byAdding: .day, value: (chosenIndex - 1) * 7, to: firstMatch)
            else { return nil }
            result.append(day)
        }
        return result
    }

    /// 開始月から offset か月後の、その月1日（開始時刻）
    private static func targetMonthStart(offset: Int, from startDay: Date,
                                         calendar: Calendar) -> Date? {
        let base = calendar.dateComponents([.year, .month], from: startDay)
        guard let year = base.year, let month = base.month else { return nil }
        let total = year * 12 + (month - 1) + offset
        var components = DateComponents()
        components.year = total / 12
        components.month = total % 12 + 1
        components.day = 1
        return calendar.date(from: components)
    }
}
