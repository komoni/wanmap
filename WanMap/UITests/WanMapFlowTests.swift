import XCTest

/// 仮想ユーザーE2Eフロー検証（フェーズP）
///
/// 目的：実機（TestFlight）前に、「本当にアプリとして使える」ことを
/// シミュレータ上の実操作で証明すること。主要なユーザー操作フローを
/// UIテストとして実行し、各フローの最後にスクリーンショット
/// （XCTAttachment・keepAlways）を残す。CI の wanmap-screenshots
/// アーティファクトで、画面撮影（WanMapScreenshotTests）と並べて確認できる。
///
/// 起動引数：
/// - -UITestingSeedData：仮想ユーザーのシード予定で起動（画面撮影と同じ）
/// - -UITestingFlowData：加えてモック現在地（ドッグウィズ付近）を1回流し込む。
///   実GPSの無いシミュレータでも「今ここ」のON/OFFを検証するための
///   DEBUG専用経路（RootView 側で MockLocationManager に差し替える）。
///   画面撮影側はこの引数を付けないので、撮影される画面は従来どおり。
/// - フロー7だけは上記を使わず、-UITestingPersistentPlans（＋初回のみ
///   -UITestingPersistentPlansReset）で隔離した永続保存先を使う。
///   シードは再起動で残らないため、「再起動しても予定が残る」証明はこちらで担う。
///
/// 状態の後片付け：チップ色はデフォルト（ラベンダー）に戻し、友達承認は
/// 設定のデータリセットで初期モックに戻す。後続の画面撮影に影響を残さないため。
///
/// 対象外：地図マーカーのタップ（座標依存で不安定なため、従来方針どおり外す）。
final class WanMapFlowTests: XCTestCase {

    private var app: XCUIApplication!
    /// 割り込みモニタのトークン（テスト中保持しておく）
    private var interruptionMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-UITestingSeedData", "-UITestingFlowData"]

        // 起動直後に出うるシステムの許可アラートを捌く（画面撮影側と同じ構え。
        // フロー検証ではモック位置を使うため通常は出ないが、保険として置く）。
        interruptionMonitor = addUIInterruptionMonitor(withDescription: "位置情報の許可アラート") { alert in
            for label in ["Allow While Using App", "アプリの使用中は許可", "Appの使用中は許可",
                          "Allow Once", "一度だけ許可"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let interruptionMonitor {
            removeUIInterruptionMonitor(interruptionMonitor)
        }
        app = nil
    }

    // MARK: - フロー1：予定の追加

    /// カレンダーの今日セル → 日別予定 → 予定追加（候補地検索で施設を選び、犬の名前を入力）
    /// → 保存 → 日別一覧に反映され、カレンダーを開き直しても残っていることを確認する。
    func test01_addPlan() throws {
        launchAndSettleOnCalendar()
        openTodayDayPlans()

        // 予定追加フォームを開く
        let addButton = app.buttons["dayPlansAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10),
                      "予定追加ボタンが見つかりませんでした")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "予定追加フォームが開きませんでした")

        // 場所：候補地検索で既存施設「ドッグウィズ」を選ぶ
        let placeField = app.textFields["場所を検索"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 10),
                      "場所の検索欄が見つかりませんでした")
        placeField.tap()
        placeField.typeText("ドッグウィズ")
        let candidate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'ドッグウィズ'")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10),
                      "施設の候補が出ませんでした")
        candidate.tap()
        XCTAssertTrue(app.staticTexts["ドッグウィズ"].waitForExistence(timeout: 10),
                      "施設が選択状態になりませんでした")

        // 犬の名前：初期値（前回の使い回し名）を消してから入れる
        let dogField = app.textFields["犬の名前"]
        XCTAssertTrue(dogField.waitForExistence(timeout: 10),
                      "犬の名前欄が見つかりませんでした")
        dogField.tap()
        if let value = dogField.value as? String, !value.isEmpty {
            dogField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                     count: value.count))
        }
        dogField.typeText("ポチ")

        // 保存 → 日別一覧に戻り、新しい予定（犬の名前「ポチ」を含む行）が見える
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ポチ'")).firstMatch
            .waitForExistence(timeout: 10),
            "保存した予定が日別一覧に反映されませんでした")

        // カレンダーに戻って開き直しても残っていること（保存が一時的でないこと）
        dismissTopSheetByDrag()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "カレンダーに戻れませんでした")
        openTodayDayPlans()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ポチ'")).firstMatch
            .waitForExistence(timeout: 10),
            "開き直した日別一覧に予定が残っていませんでした")
        attachScreenshot("flow01-add-plan")
        dismissTopSheetByDrag()
    }

    // MARK: - フロー2：「今ここ」のON/OFF

    /// 地図タブで「今ここ」をタップ → 表示が「取消」に切り替わる → もう一度タップで戻る。
    /// 現在地はモック（-UITestingFlowData）。実GPSの挙動確認は TestFlight 段階で行う。
    func test02_presenceToggle() throws {
        launchAndSettleOnCalendar()
        app.tabBars.buttons["地図"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15),
                      "地図が表示されませんでした")
        // タイルとマーカーの描画が落ち着くまで待つ
        Thread.sleep(forTimeInterval: 2)

        let onButton = app.buttons["今ここ"]
        let offButton = app.buttons["取消"]
        XCTAssertTrue(onButton.waitForExistence(timeout: 10),
                      "「今ここ」ボタンが見つかりませんでした")

        // モック現在地の到達がタップより遅れる場合があるため、表示が切り替わるまで
        // 最大3回までタップを試す（到達前のタップはステータス表示だけで無害）。
        var turnedOn = false
        for _ in 0..<3 where !turnedOn {
            onButton.tap()
            turnedOn = offButton.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(turnedOn,
                      "「今ここ」をタップしても表示が「取消」に切り替わりませんでした")
        attachScreenshot("flow02-presence-on")

        offButton.tap()
        XCTAssertTrue(onButton.waitForExistence(timeout: 10),
                      "取り消しても「今ここ」に戻りませんでした")
        attachScreenshot("flow02-presence-off")
    }

    // MARK: - フロー3：チップ色の変更反映

    /// 設定で「予定チップの色」をミントに変え、カレンダーに戻って予定チップが
    /// 存在することを確認する（色の変化そのものはスクリーンショットで目視確認）。
    /// 最後にデフォルト（ラベンダー）へ戻す。
    func test03_chipColor() throws {
        launchAndSettleOnCalendar()
        openSettings()

        let mint = app.buttons["ミント"]
        XCTAssertTrue(mint.waitForExistence(timeout: 10),
                      "ミントのスウォッチが見つかりませんでした")
        mint.tap()
        // 選択中の色名表示が「ミント」に変わる（スウォッチ自体はボタンなので、
        // staticText で拾えるのは下部の色名表示だけ）
        XCTAssertTrue(app.staticTexts["ミント"].waitForExistence(timeout: 10),
                      "選択中の色名がミントに変わりませんでした")

        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "カレンダーに戻れませんでした")
        let chip = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'SK'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "カレンダーの予定チップが見つかりませんでした")
        attachScreenshot("flow03-chip-color-mint")

        // 後片付け：デフォルト（ラベンダー）に戻し、後続の画面撮影に影響を残さない
        openSettings()
        let lavender = app.buttons["ラベンダー"]
        XCTAssertTrue(lavender.waitForExistence(timeout: 10),
                      "ラベンダーのスウォッチが見つかりませんでした")
        lavender.tap()
        XCTAssertTrue(app.staticTexts["ラベンダー"].waitForExistence(timeout: 10),
                      "選択中の色名がラベンダーに戻りませんでした")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "カレンダーに戻れませんでした")
    }

    // MARK: - フロー4：テキスト取り込み

    /// 文面（施設名＋日付表現＋時間帯の語）を貼る → 下書き候補が出る →
    /// タップすると予定フォームが開くことを確認する（自動保存はされない前提のフロー）。
    func test04_storyImport() throws {
        launchAndSettleOnCalendar()
        let importButton = app.buttons["calendarStoryImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15),
                      "取り込みボタンが見つかりませんでした")
        importButton.tap()
        XCTAssertTrue(app.navigationBars["テキストから取り込む"].waitForExistence(timeout: 15),
                      "取り込み画面が開きませんでした")

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10),
                      "文面の入力欄が見つかりませんでした")
        editor.tap()
        editor.typeText("明日はドッグウィズに行く予定！朝からたくさん遊ぶよ")

        let parseButton = app.buttons["下書きを作る"]
        XCTAssertTrue(parseButton.waitForExistence(timeout: 10),
                      "「下書きを作る」ボタンが見つかりませんでした")
        parseButton.tap()

        // 場所が名前で一致し日付表現も明示的なので、確度は「中」で候補が出る
        XCTAssertTrue(app.staticTexts["推測：中"].waitForExistence(timeout: 10),
                      "下書き候補が表示されませんでした")

        // 下書きをタップ → 予定フォームが開く
        let draft = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '推測：中'")).firstMatch
        if draft.waitForExistence(timeout: 5) {
            draft.tap()
        } else {
            app.staticTexts["推測：中"]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "下書きから予定フォームが開きませんでした")
        attachScreenshot("flow04-story-import-form")
    }

    // MARK: - フロー5：友達申請の承認

    /// 届いている申請（シードの仮想ユーザー ムギ）を承認し、友達一覧に
    /// 表示されることを確認する。最後にデータリセットで初期モックへ戻す。
    func test05_friendApprove() throws {
        launchAndSettleOnCalendar()
        let friendsButton = app.buttons["calendarFriendsButton"]
        XCTAssertTrue(friendsButton.waitForExistence(timeout: 15),
                      "友達ボタンが見つかりませんでした")
        friendsButton.tap()
        XCTAssertTrue(app.navigationBars["友達"].waitForExistence(timeout: 15),
                      "友達画面が開きませんでした")

        // シードの受信申請（ムギ）がある
        let approveButton = app.buttons["承認"]
        XCTAssertTrue(approveButton.waitForExistence(timeout: 10),
                      "ムギからの申請が見つかりませんでした")
        XCTAssertTrue(app.staticTexts["🐶 ムギ"].exists,
                      "申請者（ムギ）の行が見つかりませんでした")

        approveButton.tap()

        // 承認され、友達一覧側に移る（完了メッセージと友達行の「見せない」トグルで確認）
        XCTAssertTrue(app.staticTexts["ムギ さんと友達になりました"].waitForExistence(timeout: 10),
                      "承認の完了表示が出ませんでした")
        XCTAssertTrue(app.switches["見せない"].waitForExistence(timeout: 10),
                      "友達一覧にムギが表示されませんでした")
        XCTAssertFalse(app.buttons["承認"].waitForExistence(timeout: 3),
                       "承認後も申請が残っています")
        attachScreenshot("flow05-friend-approved")

        resetFriendStateForLaterTests()
    }

    // MARK: - フロー6：繰り返し予定の作成

    /// 予定追加フォームで「毎週」×3回を選び、プレビュー（全3回）を確認して保存 →
    /// 今日の日別一覧に反映され、開き直しても残っていることを確認する。
    /// 2回目・3回目の日付そのものの検証は単体テスト（RecurrenceGeneratorTests／
    /// PlanStoreSeriesTests）で担保し、ここではフォームと保存の配線を見る。
    func test06_createWeeklySeries() throws {
        launchAndSettleOnCalendar()
        openTodayDayPlans()

        let addButton = app.buttons["dayPlansAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10),
                      "予定追加ボタンが見つかりませんでした")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "予定追加フォームが開きませんでした")

        // 場所：候補地検索で既存施設「ドッグウィズ」を選ぶ（フロー1と同じ経路）
        let placeField = app.textFields["場所を検索"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 10),
                      "場所の検索欄が見つかりませんでした")
        placeField.tap()
        placeField.typeText("ドッグウィズ")
        let candidate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'ドッグウィズ'")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10),
                      "施設の候補が出ませんでした")
        candidate.tap()

        // 繰り返し：「毎週」を選ぶ（回数はデフォルトの3回のまま）
        let weeklySegment = app.buttons["毎週"]
        var attempts = 0
        while !weeklySegment.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(weeklySegment.exists && weeklySegment.isHittable,
                      "繰り返しの「毎週」が見つかりませんでした")
        weeklySegment.tap()

        // プレビューに全3回分の日付が出る
        XCTAssertTrue(app.staticTexts["全3回"].waitForExistence(timeout: 10),
                      "繰り返しのプレビュー（全3回）が表示されませんでした")

        // 犬の名前（他のフロー・シードと被らない名前を使う）
        let dogField = app.textFields["犬の名前"]
        attempts = 0
        while !dogField.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(dogField.waitForExistence(timeout: 10),
                      "犬の名前欄が見つかりませんでした")
        dogField.tap()
        if let value = dogField.value as? String, !value.isEmpty {
            dogField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                     count: value.count))
        }
        dogField.typeText("ムサシ")

        // 保存 → 今日の日別一覧にシリーズの初回（犬名ムサシ）が出る
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ムサシ'")).firstMatch
            .waitForExistence(timeout: 10),
            "保存した繰り返し予定が日別一覧に反映されませんでした")
        attachScreenshot("flow06-weekly-series")

        // カレンダーに戻って開き直しても残っていること
        dismissTopSheetByDrag()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "カレンダーに戻れませんでした")
        openTodayDayPlans()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ムサシ'")).firstMatch
            .waitForExistence(timeout: 10),
            "開き直した日別一覧に繰り返し予定が残っていませんでした")
        dismissTopSheetByDrag()
    }

    // MARK: - フロー7：愛ハス定例デモ（第1日曜日シリーズの永続保持）

    /// 愛ハス定例デモの通し確認。隔離した永続保存先（-UITestingPersistentPlans）で
    /// 起動し、「毎月第1日曜日」×3回を実フォームから登録 → 月表示・年表示・
    /// 日別一覧で確認 → 1回だけ時間帯を変更 → 地図で初回日を選ぶ →
    /// 終了・再起動しても登録と変更が残る → 1回を削除しても再起動で復活しない、
    /// までを実操作で通す。
    /// 固定日付（2026-12-06／2027-01-03／2027-02-07）の厳密な検証は単体テスト
    /// （AichiDemoAcceptanceTests）が担い、こちらは実行日から見た直近の
    /// 第1日曜日×3回を使う（DEMO_SPEC のハイブリッド構成）。
    func test07_aichiMonthlySeriesPersistence() throws {
        // このフローだけ起動引数を差し替える（シードは使わない）
        app.launchArguments = ["-UITestingPersistentPlans", "-UITestingPersistentPlansReset"]

        let cal = Calendar.current
        let today = Date()
        let nextMonth = cal.date(byAdding: .month, value: 1, to: today)!
        let first1 = firstSunday(inMonthOf: nextMonth, calendar: cal)
        let first2 = firstSunday(inMonthOf: cal.date(byAdding: .month, value: 1, to: nextMonth)!,
                                 calendar: cal)
        let first3 = firstSunday(inMonthOf: cal.date(byAdding: .month, value: 2, to: nextMonth)!,
                                 calendar: cal)
        // カレンダーの表示月はテスト側でも追跡する（再起動すると今月へ戻る）
        var displayed = today

        // --- 登録：初回の日別一覧からフォームを開き、第○曜日×3回で保存する ---
        launchAndSettleOnCalendar()
        navigateCalendar(toMonthContaining: first1, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first1))

        let addButton = app.buttons["dayPlansAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10),
                      "予定追加ボタンが見つかりませんでした")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "予定追加フォームが開きませんでした")

        // 場所：候補地検索で施設「ドッグウィズ」を選ぶ（フロー1と同じ経路）
        let placeField = app.textFields["場所を検索"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 10),
                      "場所の検索欄が見つかりませんでした")
        placeField.tap()
        placeField.typeText("ドッグウィズ")
        let candidate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'ドッグウィズ'")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10),
                      "施設の候補が出ませんでした")
        candidate.tap()

        // 繰り返し：「第○曜日」を選ぶ（初回日が第1日曜日なので「毎月第1日曜日」になる）
        let ordinalSegment = app.buttons["第○曜日"]
        var attempts = 0
        while !ordinalSegment.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(ordinalSegment.exists && ordinalSegment.isHittable,
                      "繰り返しの「第○曜日」が見つかりませんでした")
        ordinalSegment.tap()
        XCTAssertTrue(app.staticTexts["毎月第1日曜日"].waitForExistence(timeout: 10),
                      "繰り返しの読み（毎月第1日曜日）が表示されませんでした")
        XCTAssertTrue(app.staticTexts["全3回"].waitForExistence(timeout: 10),
                      "繰り返しのプレビュー（全3回）が表示されませんでした")

        // 犬の名前（他のフロー・シードと被らない名前を使う）
        let dogField = app.textFields["犬の名前"]
        attempts = 0
        while !dogField.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(dogField.waitForExistence(timeout: 10),
                      "犬の名前欄が見つかりませんでした")
        dogField.tap()
        if let value = dogField.value as? String, !value.isEmpty {
            dogField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                     count: value.count))
        }
        dogField.typeText("ハス太")

        // 保存 → 初回の日別一覧に反映される
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "保存した定例が初回の日別一覧に反映されませんでした")
        attachScreenshot("demo-aichi-01-register")
        dismissTopSheetByDrag()

        // --- 月表示：初回月に予定チップ（場所名）が出る ---
        // 月グリッドの日別グルーピングは端末タイムゾーン基準のため、実行環境の
        // タイムゾーンによってはチップが前月末のセルへ寄ることがある。
        // その場合は前月側も確認し、日の所属そのものは日別一覧と単体テストで担保する。
        let chip = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ドッグウィズ'")).firstMatch
        if !chip.waitForExistence(timeout: 5) {
            navigateCalendar(toMonthContaining: cal.date(byAdding: .month, value: -1, to: first1)!,
                               displayedMonth: &displayed)
            XCTAssertTrue(chip.waitForExistence(timeout: 10),
                          "月表示に定例のチップが出ませんでした")
            navigateCalendar(toMonthContaining: first1, displayedMonth: &displayed)
        }
        attachScreenshot("demo-aichi-02-calendar-months")

        // --- 日別一覧：2回目・3回目にも同じ定例が出る ---
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first2))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "2回目の日別一覧に定例が出ませんでした")
        dismissTopSheetByDrag()
        navigateCalendar(toMonthContaining: first3, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first3))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "3回目の日別一覧に定例が出ませんでした")
        dismissTopSheetByDrag()

        // --- 年表示：対象年のグリッドが開く（印の厳密な照合は単体テスト側） ---
        let yearButton = app.buttons["年"]
        XCTAssertTrue(yearButton.waitForExistence(timeout: 10),
                      "年表示への切り替えが見つかりませんでした")
        yearButton.tap()
        let yearTitle = "\(cal.component(.year, from: first3))年"
        XCTAssertTrue(app.staticTexts[yearTitle].waitForExistence(timeout: 10),
                      "年表示（\(yearTitle)）が開きませんでした")
        attachScreenshot("flow07-year-view")
        app.buttons["月"].tap()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "月表示に戻れませんでした")

        // --- 1回だけ変更：2回目の時間帯だけを「夜」にする ---
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first2))
        // 行は List のセル経由でタップする（背後の月グリッドにも同じ場所名の
        // チップがあり、テキスト検索だとそちらを掴む恐れがあるため）
        let editCell = app.cells.firstMatch
        XCTAssertTrue(editCell.waitForExistence(timeout: 10),
                      "2回目の予定行が見つかりませんでした")
        editCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["予定を編集"].waitForExistence(timeout: 10),
                      "編集フォームが開きませんでした")
        // 編集範囲は「この回だけ／シリーズ全体」の2択で、初期値は「この回だけ」
        XCTAssertTrue(app.buttons["この回だけ"].waitForExistence(timeout: 10),
                      "編集範囲の選択肢が表示されませんでした")
        XCTAssertTrue(app.buttons["シリーズ全体"].exists,
                      "編集範囲の選択肢（シリーズ全体）が表示されませんでした")
        let nightSegment = app.buttons["夜"]
        attempts = 0
        while !nightSegment.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(nightSegment.exists && nightSegment.isHittable,
                      "時間帯の「夜」が見つかりませんでした")
        nightSegment.tap()
        app.buttons["保存"].tap()
        // 2回目の一覧では時間帯が「夜」に変わっている
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '夜' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "2回目の時間帯が「夜」に変わりませんでした")
        attachScreenshot("demo-aichi-03-single-edit")
        dismissTopSheetByDrag()
        // 初回は元の時間帯（終日）のまま変わっていない
        navigateCalendar(toMonthContaining: first1, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first1))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '終日' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "初回の時間帯が元のまま（終日）ではありませんでした")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '夜' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 3),
            "初回まで「夜」に変わってしまいました")
        dismissTopSheetByDrag()

        // --- 地図：初回の日を選ぶと、友達レールに登録した犬が出る ---
        app.tabBars.buttons["地図"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15),
                      "地図が表示されませんでした")
        Thread.sleep(forTimeInterval: 2)
        let stripLabel = "\(cal.component(.month, from: first1))/\(cal.component(.day, from: first1))(日)"
        selectMapDay(label: stripLabel)
        // 友達レールは座標のある予定から組み立てられる（初文字がラベルになる）
        XCTAssertTrue(app.buttons["ハ"].waitForExistence(timeout: 10),
                      "地図の友達レールに登録した犬が出ませんでした")
        attachScreenshot("demo-aichi-04-map")

        // --- 再起動：終了してもう一度開くと、登録と単回変更がそのまま残る ---
        app.terminate()
        app.launchArguments = ["-UITestingPersistentPlans"]  // リセットは付けない
        displayed = today
        launchAndSettleOnCalendar()
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first2))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '夜' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "再起動後に2回目の変更（夜）が残っていませんでした")
        attachScreenshot("demo-aichi-05-after-restart")

        // --- 個別削除：2回目だけを消し、再起動しても復活しないことを確認する ---
        let deleteCell = app.cells.firstMatch
        XCTAssertTrue(deleteCell.waitForExistence(timeout: 10),
                      "削除対象の予定行が見つかりませんでした")
        deleteCell.swipeLeft()
        let swipeDelete = app.buttons["削除"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 10),
                      "スワイプ削除のボタンが出ませんでした")
        swipeDelete.tap()
        let deleteOccurrence = app.buttons["この回だけ削除"]
        XCTAssertTrue(deleteOccurrence.waitForExistence(timeout: 10),
                      "削除範囲のダイアログが出ませんでした")
        deleteOccurrence.tap()
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 3),
            "削除した回がその場で消えていません")
        dismissTopSheetByDrag()

        app.terminate()
        app.launchArguments = ["-UITestingPersistentPlans"]
        displayed = today
        launchAndSettleOnCalendar()
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first2))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 3),
            "削除した回が再起動で復活しました")
        dismissTopSheetByDrag()
        // 初回は残っている（シリーズごと消えていない）
        navigateCalendar(toMonthContaining: first1, displayedMonth: &displayed)
        openDayPlans(dayNumber: cal.component(.day, from: first1))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '終日' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "初回の定例まで消えてしまいました")
        dismissTopSheetByDrag()
    }

    /// 指定した日を含む月の第1日曜日
    private func firstSunday(inMonthOf date: Date, calendar: Calendar) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let weekday = calendar.component(.weekday, from: first)
        return calendar.date(byAdding: .day, value: (1 - weekday + 7) % 7, to: first)!
    }

    /// カレンダーの表示月を target の月まで送る／戻し、見出しで到達を確認する。
    /// displayedMonth はテスト側で追跡する現在表示中の月（呼び出し側で更新する）。
    private func navigateCalendar(toMonthContaining target: Date, displayedMonth: inout Date) {
        let cal = Calendar.current
        let from = cal.dateComponents([.year, .month], from: displayedMonth)
        let to = cal.dateComponents([.year, .month], from: target)
        var delta = (to.year! - from.year!) * 12 + (to.month! - from.month!)
        while delta > 0 {
            app.buttons["calendarNextMonthButton"].tap()
            delta -= 1
        }
        while delta < 0 {
            app.buttons["calendarPrevMonthButton"].tap()
            delta += 1
        }
        displayedMonth = cal.date(from: to)!
        let title = "\(to.year!)年\(to.month!)月"
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10),
                      "カレンダーの見出しが \(title) になりませんでした")
    }

    /// 月表示で dayNumber 日のセルをタップし、日別予定シートが開くことを確認する
    private func openDayPlans(dayNumber: Int) {
        let cell = app.staticTexts.matching(
            NSPredicate(format: "label == '%d'", dayNumber)).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10),
                      "\(dayNumber)日のセルが見つかりませんでした")
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dayTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '月' AND label CONTAINS '日'")).firstMatch
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 15),
                      "日別予定シートが開きませんでした")
    }

    /// 地図の日付ストリップを横スクロールしながら、対象日のボタンを選ぶ
    private func selectMapDay(label: String) {
        let button = app.buttons[label]
        var attempts = 0
        while !button.isHittable && attempts < 20 {
            app.scrollViews.firstMatch.swipeLeft()
            attempts += 1
        }
        XCTAssertTrue(button.exists && button.isHittable,
                      "地図の日付ボタン \(label) が見つかりませんでした")
        button.tap()
    }

    // MARK: - 共通処理

    /// シード付きで起動し、カレンダー表示で落ち着かせる（画面撮影側と同じ手順）
    private func launchAndSettleOnCalendar() {
        app.launch()

        let calendarTab = app.tabBars.buttons["カレンダー"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 30),
                      "タブバーが表示されませんでした")
        Thread.sleep(forTimeInterval: 2)
        calendarTab.tap()

        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 15),
                      "カレンダー画面が表示されませんでした")
        Thread.sleep(forTimeInterval: 1)
    }

    /// 今日のセルをタップして日別予定シートを開く。
    /// 今日セルには小さな肉球（🐾）が付くので、その中心座標でタップして
    /// セル全体のタップ判定に乗せる。見つからなければシード予定のチップ経由。
    private func openTodayDayPlans() {
        let paw = app.staticTexts["🐾"]
        if paw.waitForExistence(timeout: 10) {
            paw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            let chip = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'SK'")).firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 10),
                          "今日のセルが見つかりませんでした")
            chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        // 日別予定シートのタイトルは「M月d日（E）」形式。画面撮影側と同じ判定
        // （「月」と「日」を両方含むテキストはカレンダー画面側には無い）。
        let dayTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '月' AND label CONTAINS '日'")).firstMatch
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 15),
                      "日別予定シートが開きませんでした")
    }

    /// 設定画面を開く（画面撮影側と同じ経路）
    private func openSettings() {
        let settingsButton = app.buttons["calendarSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15),
                      "設定ボタンが見つかりませんでした")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15),
                      "設定画面が開きませんでした")
    }

    /// 一番上のシートを下ドラッグで閉じる（日別予定シートには閉じるボタンが無いため）
    private func dismissTopSheetByDrag() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.15, thenDragTo: finish)
    }

    /// フロー5の後片付け（ベストエフォート）：設定の「データをリセット」で
    /// 友達状態を初期モック（ムギからの申請1件）に戻し、後続の画面撮影
    /// （設定画面の「見せない相手」欄）に影響を残さない。
    /// ここが失敗してもフロー自体の合否には影響させない。
    private func resetFriendStateForLaterTests() {
        let closeButton = app.buttons["閉じる"]
        guard closeButton.waitForExistence(timeout: 5) else { return }
        closeButton.tap()

        let settingsButton = app.buttons["calendarSettingsButton"]
        guard settingsButton.waitForExistence(timeout: 10) else { return }
        settingsButton.tap()
        guard app.navigationBars["設定"].waitForExistence(timeout: 10) else { return }

        let resetButton = app.buttons["データをリセット"]
        var attempts = 0
        while !resetButton.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        guard resetButton.exists && resetButton.isHittable else { return }
        resetButton.tap()

        let deleteButton = app.buttons["すべて消す"]
        guard deleteButton.waitForExistence(timeout: 5) else { return }
        deleteButton.tap()

        let closeSettings = app.buttons["閉じる"]
        if closeSettings.waitForExistence(timeout: 5) {
            closeSettings.tap()
        }
    }

    /// スクリーンショットをテスト結果へ添付する（合格時も残すため keepAlways）
    private func attachScreenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
