#if DEBUG
import Foundation

/// 仮想ユーザーの予定データ（プレビュー／デバッグ専用）
/// テスト方針「仮想使用者を作って予定を入れて検証する」のための素材。
/// 通常起動時の実データには混ぜない（PlanStore(samplePlans:) 経由でのみ使う）。
enum SeedData {
    static func samplePlans(now: Date = Date()) -> [Plan] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)  // 1=日曜 … 7=土曜

        func day(offsetFromToday offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: today) ?? today
        }
        // 次の日曜（今日が日曜なら来週）と直近の土曜
        var sundayOffset = (8 - weekday) % 7
        if sundayOffset == 0 { sundayOffset = 7 }
        let saturdayOffset = (7 - weekday + 7) % 7

        let dogWith = (lat: 35.1649375, lng: 137.08455)        // ドッグウィズ
        let skRun = (lat: 34.7921028, lng: 137.0232936)        // SKドッグラン
        let seasons = (lat: 35.4408176, lng: 136.8299529)      // season's（岐阜市）

        func plan(person: String, dog: String, place: String,
                  lat: Double?, lng: Double?, date: Date,
                  band: TimeBand, level: AttendanceLevel,
                  isEvent: Bool = false, deadline: Date? = nil,
                  isPresence: Bool = false, createdAt: Date? = nil) -> Plan {
            Plan(id: UUID(), personName: person, dogName: dog, placeName: place,
                 latitude: lat, longitude: lng, date: date, timeBand: band, level: level,
                 isEvent: isEvent, eventDeadline: deadline,
                 isPresence: isPresence, createdAt: createdAt ?? now)
        }

        return [
            // 今日：モモがSKドッグランに来ている想定（今日のセルに必ず何か出る）
            plan(person: "ユイ", dog: "モモ", place: "SKドッグラン",
                 lat: skRun.lat, lng: skRun.lng, date: today,
                 band: .morning, level: .going),
            // 直近の土曜：SKドッグランでモモとコタロウが重なる
            plan(person: "ユイ", dog: "モモ", place: "SKドッグラン",
                 lat: skRun.lat, lng: skRun.lng, date: day(offsetFromToday: saturdayOffset),
                 band: .noon, level: .going),
            plan(person: "シン", dog: "コタロウ", place: "SKドッグラン",
                 lat: skRun.lat, lng: skRun.lng, date: day(offsetFromToday: saturdayOffset),
                 band: .noon, level: .ifSunny),
            // 次の日曜：ドッグウィズの定例にソラとハルが重なる
            plan(person: "タクミ", dog: "ソラ", place: "ドッグウィズ",
                 lat: dogWith.lat, lng: dogWith.lng, date: day(offsetFromToday: sundayOffset),
                 band: .morning, level: .going),
            plan(person: "ミサキ", dog: "ハル", place: "ドッグウィズ",
                 lat: dogWith.lat, lng: dogWith.lng, date: day(offsetFromToday: sundayOffset),
                 band: .morning, level: .probably),
            // 次の日曜：レオ主催のイベント（募集）。締め切りは2日前
            plan(person: "あかり", dog: "レオ", place: "ドッグウィズ",
                 lat: dogWith.lat, lng: dogWith.lng, date: day(offsetFromToday: sundayOffset),
                 band: .noon, level: .going,
                 isEvent: true, deadline: day(offsetFromToday: sundayOffset - 2)),
            // 明後日：ムギが season's
            plan(person: "ケン", dog: "ムギ", place: "season's",
                 lat: seasons.lat, lng: seasons.lng, date: day(offsetFromToday: 2),
                 band: .morning, level: .probably),
            // 昨日終わったイベント（イベントタブで隠れることの確認用）
            plan(person: "あかり", dog: "レオ", place: "SKドッグラン",
                 lat: skRun.lat, lng: skRun.lng, date: day(offsetFromToday: -1),
                 band: .noon, level: .going,
                 isEvent: true, deadline: day(offsetFromToday: -3)),
            // 「今ここ」：ソラがドッグウィズ付近にいる（場所名なし＝人アイコンのみ想定も含め、
            // ここでは登録済み場所に紐付く形。作成時刻は今なので2時間は表示される）
            plan(person: "タクミ", dog: "ソラ", place: "ドッグウィズ",
                 lat: dogWith.lat, lng: dogWith.lng, date: today,
                 band: .allDay, level: .going,
                 isPresence: true, createdAt: now),
        ]
    }
}
#endif
