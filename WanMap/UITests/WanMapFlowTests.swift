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
/// - 全フロー共通で -AppleLanguages (ja) / -AppleLocale ja_JP も付け、
///   OSが合成するボタン（スワイプ削除の「削除」など）の表記を日本語に固定し、
///   CIシミュレータの言語設定に左右されないようにする（CI #38 対応）。
///   フロー7の再起動時もこの2引数は落とさない。
///
/// 状態の後片付け：チップ色はデフォルト（ラベンダー）に戻し、友達承認は
/// 設定のデータリセットで初期モックに戻す。後続の画面撮影に影響を残さないため。
///
/// 対象外：地図マーカーのタップ（座標依存で不安定なため、従来方針どおり外す）。
final class WanMapFlowTests: XCTestCase {

    /// ロケール固定の起動引数（全フロー共通）。起動引数を差し替える
    /// フロー7でも、必ずこの2引数を足してから使うこと。
    private static let localeArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]

    private var app: XCUIApplication!
    /// 割り込みモニタのトークン（テスト中保持しておく）
    private var interruptionMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-UITestingSeedData", "-UITestingFlowData"] + Self.localeArguments

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

        let expectedText = "明日はドッグウィズに行く予定！朝からたくさん遊ぶよ"
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10),
                      "文面の入力欄が見つかりませんでした")
        editor.tap()
        editor.typeText(expectedText)

        // 入力した文面がそのまま入っているか、値で確認する。日本語入力の
        // 確定タイミングで欠落・重複が起きていた場合だけ、全消去して
        // 1回まで入れ直す（解析を連打するような再試行はしない。
        // UI_TEST_FIX_TRIAGE の採否どおり）。
        if !waitForTextValue(of: editor, toEqual: expectedText, timeout: 5) {
            if let current = editor.value as? String, !current.isEmpty {
                editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                       count: current.count))
            }
            editor.typeText(expectedText)
            let note = XCTAttachment(
                string: "入力値が期待文と一致しなかったため、全消去して再入力しました（1回）。")
            note.name = "flow04-story-import-input-retry"
            note.lifetime = .keepAlways
            add(note)
            if !waitForTextValue(of: editor, toEqual: expectedText, timeout: 5) {
                attachFailureEvidence("flow04-input-mismatch", element: editor)
                XCTFail("文面が正しく入力できませんでした")
            }
        }

        // 「下書きを作る」は、存在するだけでなく操作できる状態
        // （有効＋タップ可能。空欄の間はアプリ側で無効になる）になってから押す
        let parseButton = app.buttons["下書きを作る"]
        let parseReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: parseButton)
        if XCTWaiter().wait(for: [parseReady], timeout: 10) != .completed {
            attachFailureEvidence("flow04-parse-button-not-ready", element: parseButton)
            XCTFail("「下書きを作る」ボタンが操作可能になりませんでした")
        }
        parseButton.tap()

        // 場所が名前で一致し日付表現も明示的なので、確度は「中」で候補が出る。
        // 候補は Button（場所名・確度など複数のテキストを持つ行）として探す。
        // 確度だけの StaticText はボタンラベルへ統合されて独立に公開されない
        // ことがあるため、待ちの対象にしない（確度「中」の要求自体は緩めない）。
        let draft = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'ドッグウィズ' AND label CONTAINS '推測：中'"))
            .firstMatch
        if !draft.waitForExistence(timeout: 10) {
            attachFailureEvidence("flow04-draft-not-found", element: editor)
            XCTFail("下書き候補（ドッグウィズ／推測：中）が表示されませんでした")
        }

        // 下書きをタップ → 予定フォームが開く
        draft.tap()
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
            + Self.localeArguments

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
        openDayPlans(on: first1)

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
        openDayPlans(on: first2)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "2回目の日別一覧に定例が出ませんでした")
        dismissTopSheetByDrag()
        navigateCalendar(toMonthContaining: first3, displayedMonth: &displayed)
        openDayPlans(on: first3)
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
        openDayPlans(on: first2)
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
        openDayPlans(on: first1)
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
        // 日付帯のスワイプ探索は1回の移動量が大きく対象日を飛び越すため
        // （CI #77〜#80で連続失敗。失敗時の画面録画で、帯が対象日を通り過ぎて
        // 範囲の末尾まで進んでいたことを確認）、DEBUG用の引数 -wmMapDate で
        // 地図を対象日から開く形に変えた。再起動を挟むため永続化の確認も兼ねる。
        let first1Components = Calendar.current.dateComponents([.year, .month, .day], from: first1)
        let first1Argument = String(format: "%04d-%02d-%02d",
                                    first1Components.year ?? 0,
                                    first1Components.month ?? 0,
                                    first1Components.day ?? 0)
        app.terminate()
        app.launchArguments = ["-UITestingPersistentPlans", "-wmMapDate", first1Argument] + Self.localeArguments
        launchAndSettleOnCalendar()
        app.tabBars.buttons["地図"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15),
                      "地図が表示されませんでした")
        Thread.sleep(forTimeInterval: 2)
        selectMapDay(on: first1)
        // 友達レールは座標のある予定から組み立てられる（初文字がラベルになる）
        XCTAssertTrue(app.buttons["ハ"].waitForExistence(timeout: 10),
                      "地図の友達レールに登録した犬が出ませんでした")
        attachScreenshot("demo-aichi-04-map")

        // --- 再起動：終了してもう一度開くと、登録と単回変更がそのまま残る ---
        app.terminate()
        app.launchArguments = ["-UITestingPersistentPlans"] + Self.localeArguments  // リセットは付けない
        displayed = today
        launchAndSettleOnCalendar()
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(on: first2)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '夜' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "再起動後に2回目の変更（夜）が残っていませんでした")
        attachScreenshot("demo-aichi-05-after-restart")

        // --- 個別削除：2回目だけを消し、再起動しても復活しないことを確認する ---
        // 対象行は、削除する回そのものを指すテキスト要素（「夜」に変更済みの
        // 2回目で、犬名「ハス太」を含む StaticText）で一意に特定する。
        // セル要素のラベルには犬名が含まれず、cells のラベル検索では行を
        // 掴めなかったため（CI #39）、行の特定はテキスト要素に寄せ、
        // スワイプもその座標から行う（共通処理に委譲）。
        let targetRows = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '夜' AND label CONTAINS 'ハス太'"))
        XCTAssertEqual(targetRows.count, 1,
                       "削除対象の行が一意に特定できませんでした（\(targetRows.count) 件）")
        swipeDayPlanRowAndDeleteOccurrence(rowText: targetRows.firstMatch,
                                           evidenceName: "flow07-delete-not-reached")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 3),
            "削除した回がその場で消えていません")
        dismissTopSheetByDrag()

        app.terminate()
        app.launchArguments = ["-UITestingPersistentPlans"] + Self.localeArguments
        displayed = today
        launchAndSettleOnCalendar()
        navigateCalendar(toMonthContaining: first2, displayedMonth: &displayed)
        openDayPlans(on: first2)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 3),
            "削除した回が再起動で復活しました")
        dismissTopSheetByDrag()
        // 初回は残っている（シリーズごと消えていない）
        navigateCalendar(toMonthContaining: first1, displayedMonth: &displayed)
        openDayPlans(on: first1)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '終日' AND label CONTAINS 'ハス太'")).firstMatch
            .waitForExistence(timeout: 10),
            "初回の定例まで消えてしまいました")
        dismissTopSheetByDrag()
    }

    // MARK: - フロー8：シリーズ1回のスワイプ削除（短い回帰テスト）

    /// 毎週シリーズ×3回を登録し、初回の日別シートで対象行を部分スワイプして
    /// 「この回だけ削除」→ その場で初回が消え、他の回が残ることだけを確認する
    /// 短い回帰テスト（CI #39 追補でフロー7の長い永続化フローから分離）。
    /// 再起動を伴う永続性（削除した回が復活しないか）はフロー7の担当で、
    /// ここには含めない。行の特定とスワイプはフロー7と共通処理・同一方式。
    func test08_swipeDeleteSeriesOccurrence() throws {
        launchAndSettleOnCalendar()
        openTodayDayPlans()

        let addButton = app.buttons["dayPlansAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10),
                      "予定追加ボタンが見つかりませんでした")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "予定追加フォームが開きませんでした")

        // 場所：候補地検索で施設「ドッグウィズ」を選ぶ（フロー6と同じ経路）
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

        // 繰り返し：「毎週」を選ぶ（回数はデフォルトの3回のまま。フロー6と同じ作り方）
        let weeklySegment = app.buttons["毎週"]
        var attempts = 0
        while !weeklySegment.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(weeklySegment.exists && weeklySegment.isHittable,
                      "繰り返しの「毎週」が見つかりませんでした")
        weeklySegment.tap()
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
        dogField.typeText("ゴン太")

        // 保存 → 初回（今日）の日別一覧に反映される
        app.buttons["保存"].tap()
        let rowQuery = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ゴン太'"))
        XCTAssertTrue(rowQuery.firstMatch.waitForExistence(timeout: 10),
                      "保存した繰り返し予定が日別一覧に反映されませんでした")

        // 初回の行を部分スワイプして「この回だけ削除」まで進める（フロー7と共通）
        XCTAssertEqual(rowQuery.count, 1,
                       "削除対象の行が一意に特定できませんでした（\(rowQuery.count) 件）")
        swipeDayPlanRowAndDeleteOccurrence(rowText: rowQuery.firstMatch,
                                           evidenceName: "flow08-delete-not-reached")

        // 初回はその場で消える。要素待ちの前にアプリの生存を確認する
        // （アプリが終了していると waitForExistence は「存在しない」を返し、
        // 削除で消えたのかアプリ終了で見えないだけなのか区別できないため）。
        assertAppRunningForeground("flow08-before-row-disappearance-check")
        XCTAssertFalse(rowQuery.firstMatch.waitForExistence(timeout: 3),
                       "削除した回がその場で消えていません")
        attachScreenshot("flow08-swipe-delete-occurrence")
        dismissTopSheetByDrag()

        // 他の回（2回目＝来週の同じ曜日）は残っている。
        // こちらも要素待ちの前にアプリ状態を添付へ残す。
        let gregorian = Calendar(identifier: .gregorian)
        let nextWeek = gregorian.date(byAdding: .day, value: 7, to: Date())!
        var displayed = Date()
        navigateCalendar(toMonthContaining: nextWeek, displayedMonth: &displayed)
        openDayPlans(on: nextWeek)
        assertAppRunningForeground("flow08-before-other-occurrence-check")
        if !app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ゴン太'")).firstMatch
            .waitForExistence(timeout: 10) {
            attachFailureEvidence("flow08-other-occurrence-missing")
            XCTFail("シリーズの他の回（2回目）まで消えてしまいました")
        }
        dismissTopSheetByDrag()
    }

    // MARK: - フロー9：シリーズ1回のフォーム削除（診断用）

    /// test08 と同じ「毎週シリーズ×3回の初回を、この回だけ削除」を、
    /// スワイプではなく編集フォーム経由で行う診断テスト。目的は切り分け専用：
    /// 「削除確定後にアプリが落ちる」事象が、スワイプ操作を引き金として
    /// 必要とするのか（フォーム経由でも同じく落ちるのか）を見る。
    /// 登録の前段（シード起動・作り方は test08 と同一手順）と検証内容
    /// （初回が消え、他の回が残る）は test08 と同等で、違うのは削除経路だけ：
    /// 行タップ→編集フォーム→「この予定を削除」→範囲ダイアログで
    /// 「この回だけ削除」。test08 側には一切手を入れていない。
    func test09_formDeleteSeriesOccurrence() throws {
        launchAndSettleOnCalendar()
        openTodayDayPlans()

        let addButton = app.buttons["dayPlansAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10),
                      "予定追加ボタンが見つかりませんでした")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["予定を追加"].waitForExistence(timeout: 10),
                      "予定追加フォームが開きませんでした")

        // 場所：候補地検索で施設「ドッグウィズ」を選ぶ（フロー6・8と同じ経路）
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

        // 繰り返し：「毎週」を選ぶ（回数はデフォルトの3回のまま。フロー8と同じ作り方）
        let weeklySegment = app.buttons["毎週"]
        var attempts = 0
        while !weeklySegment.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(weeklySegment.exists && weeklySegment.isHittable,
                      "繰り返しの「毎週」が見つかりませんでした")
        weeklySegment.tap()
        XCTAssertTrue(app.staticTexts["全3回"].waitForExistence(timeout: 10),
                      "繰り返しのプレビュー（全3回）が表示されませんでした")

        // 犬の名前（test08 と同じゴン太。シードは起動ごとに作り直されるため、
        // フローをまたいだ混線はしない）
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
        dogField.typeText("ゴン太")

        // 保存 → 初回（今日）の日別一覧に反映される
        app.buttons["保存"].tap()
        let rowQuery = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ゴン太'"))
        XCTAssertTrue(rowQuery.firstMatch.waitForExistence(timeout: 10),
                      "保存した繰り返し予定が日別一覧に反映されませんでした")
        XCTAssertEqual(rowQuery.count, 1,
                       "削除対象の行が一意に特定できませんでした（\(rowQuery.count) 件）")

        // --- ここから test08 と経路が違う：スワイプせず、行タップで編集フォームを開く ---
        // 行内のテキスト要素の座標でタップする（openTodayDayPlans の肉球タップと
        // 同じ流儀。行全体に onTapGesture が付いており、テキスト上でも発火する）。
        rowQuery.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["予定を編集"].waitForExistence(timeout: 10),
                      "編集フォームが開きませんでした")

        // フォーム最下部の削除セクション「この予定を削除」を押す。
        // Form の末尾にあるため、必要に応じてスクロールして出す。
        let formDeleteButton = app.buttons["この予定を削除"]
        attempts = 0
        while !formDeleteButton.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(formDeleteButton.exists && formDeleteButton.isHittable,
                      "フォームの削除ボタン（この予定を削除）が見つかりませんでした")
        formDeleteButton.tap()

        // 範囲ダイアログはスワイプ経路と共通の SeriesDeletionDialog
        // （タイトル「この予定は繰り返しの一部です」）。「この回だけ削除」を選ぶ。
        let deleteOccurrence = app.buttons["この回だけ削除"]
        XCTAssertTrue(deleteOccurrence.waitForExistence(timeout: 10),
                      "削除範囲のダイアログが出ませんでした")
        deleteOccurrence.tap()

        // 削除が成功すると onDeleted でフォームが自動的に閉じ、日別シートへ
        // 戻る（PlanFormView の既存挙動）。閉じるまで待ってから生存確認する。
        let formDeadline = Date().addingTimeInterval(10)
        while app.navigationBars["予定を編集"].exists && Date() < formDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(app.navigationBars["予定を編集"].exists,
                       "削除後に編集フォームが閉じませんでした")
        // 診断：フォーム経由の削除でもアプリが落ちるかを、この地点で切り分ける
        assertAppRunningForeground("flow09-after-form-delete")

        // 初回はその場で消える。要素待ちの前にアプリの生存を確認する
        // （test08 と同じ理由・同じ検証）。
        assertAppRunningForeground("flow09-before-row-disappearance-check")
        XCTAssertFalse(rowQuery.firstMatch.waitForExistence(timeout: 3),
                       "削除した回がその場で消えていません")
        attachScreenshot("flow09-form-delete-occurrence")
        dismissTopSheetByDrag()

        // 他の回（2回目＝来週の同じ曜日）は残っている（test08 と同じ検証）。
        let gregorian = Calendar(identifier: .gregorian)
        let nextWeek = gregorian.date(byAdding: .day, value: 7, to: Date())!
        var displayed = Date()
        navigateCalendar(toMonthContaining: nextWeek, displayedMonth: &displayed)
        openDayPlans(on: nextWeek)
        assertAppRunningForeground("flow09-before-other-occurrence-check")
        if !app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ゴン太'")).firstMatch
            .waitForExistence(timeout: 10) {
            attachFailureEvidence("flow09-other-occurrence-missing")
            XCTFail("シリーズの他の回（2回目）まで消えてしまいました")
        }
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

    /// 月表示で date の日のセルをタップし、日別予定シートが開くことを確認する。
    /// セルは CalendarView 側の日セル専用識別子（calendarDayCell-yyyy-MM-dd）で掴む。
    /// 以前はセル内の数字テキストを StaticText のラベル完全一致で探していたが、
    /// 数字だけの素のセルはコンテナ（タップジェスチャ付きVStack）への集約のされ方に
    /// 左右され、StaticText として安定して現れず CI で見つけられなかった。
    /// 識別子なら要素の種類に依存せず、セル全体がタップ対象になる。
    private func openDayPlans(on date: Date) {
        // 年月日の取り出しはアプリ側（Gregorian固定）に合わせる。
        // Calendar.current は端末設定で和暦等になり得るため使わない
        let gregorian = Calendar(identifier: .gregorian)
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        let identifier = String(format: "calendarDayCell-%04d-%02d-%02d",
                                c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let cell = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10),
                      "\(c.day ?? 0)日のセルが見つかりませんでした")
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dayTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '月' AND label CONTAINS '日'")).firstMatch
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 15),
                      "日別予定シートが開きませんでした")
    }

    /// 地図の日付ストリップを横スクロールしながら、対象日のボタンを選ぶ
    /// 地図の日付ストリップで対象日を選ぶ（フロー7の安定化A案）。
    /// 日付ボタンは表示ラベルでなく識別子（mapDayButton-yyyy-MM-dd）で特定し、
    /// スワイプするのはストリップ（mapDateStrip）だけに限る。以前の実装は
    /// `app.scrollViews.firstMatch` をスワイプしていたため、友達レール等の
    /// 別スクロールを誤って動かし、対象日が永遠に出ないことがあった。
    /// LazyHStack は画面外ボタンを階層に持たないことがあるので、存在と
    /// タップ可否を分けて見ながら少しずつ進め、上限まで見つからなければ
    /// タップせずに失敗させる。
    private func selectMapDay(on day: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let identifier = String(format: "mapDayButton-%04d-%02d-%02d",
                                c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let strip = app.scrollViews["mapDateStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10),
                      "地図の日付ストリップが見つかりませんでした")
        let button = app.buttons[identifier]
        var attempts = 0
        while attempts < 30 {
            if button.exists && button.isHittable {
                button.tap()
                return
            }
            strip.swipeLeft()
            attempts += 1
        }
        XCTFail("地図の日付ボタン \(identifier) がストリップ内に見つかりませんでした")
    }

    // MARK: - フロー10：自分の犬（犬種・毛色）とチップの種類

    /// 設定でチップの種類を「犬種アイコン」に変え、犬種を検索して柴犬を選び、
    /// 毛色（赤）を選ぶと、設定の要約が「柴犬・赤」になることを確認する。
    /// 最後にチップの種類を「頭文字」に戻す（後続の撮影に影響を残さない）。
    /// 犬種・毛色の選択自体は残してよい（自分の犬の設定は初期モックに含まれない）。
    func test10_breedSetting() throws {
        launchAndSettleOnCalendar()
        openSettings()

        // チップの種類を「犬種アイコン」へ（Picker はメニュー形式）
        let chipPicker = app.buttons["markerChipStylePicker"]
        XCTAssertTrue(chipPicker.waitForExistence(timeout: 10),
                      "チップの種類のピッカーが見つかりませんでした")
        chipPicker.tap()
        let breedIconItem = app.buttons["犬種アイコン"]
        XCTAssertTrue(breedIconItem.waitForExistence(timeout: 10),
                      "「犬種アイコン」の選択肢が出ませんでした")
        breedIconItem.tap()

        // 犬種選択画面へ。一覧（人気順）から柴犬を選ぶ。
        // 検索入力はこのフローでは経由しない（検索そのものの確認は単体テストと
        // 撮影テスト13が担う）。なお行タップが効かなかった件（CI #67〜#71）は
        // キーボードのせいではなく、行ボタンの .plain＋Spacer で中央が
        // タップ判定外になっていたのが原因で、アプリ側で修正済み
        let breedLink = app.buttons["breedPickerLink"]
        XCTAssertTrue(breedLink.waitForExistence(timeout: 10),
                      "犬種の行が見つかりませんでした")
        breedLink.tap()
        XCTAssertTrue(app.navigationBars["犬種を選ぶ"].waitForExistence(timeout: 10),
                      "犬種選択画面が開きませんでした")
        let shibaRow = app.buttons["breedRow_shiba"]
        XCTAssertTrue(shibaRow.waitForExistence(timeout: 10),
                      "一覧に柴犬が出ませんでした")
        shibaRow.tap()
        // 遷移が遅い場合に備え、設定に戻らなければもう一度タップする
        if !app.navigationBars["設定"].waitForExistence(timeout: 8), shibaRow.exists {
            shibaRow.tap()
        }
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15),
                      "設定画面に戻れませんでした")
        XCTAssertTrue(app.staticTexts["柴犬"].waitForExistence(timeout: 10),
                      "設定に犬種（柴犬）が反映されませんでした")

        // 毛色（赤）を選ぶと要約が「柴犬・赤」になる
        let redCell = app.buttons["breedColor_red"]
        XCTAssertTrue(redCell.waitForExistence(timeout: 10),
                      "毛色（赤）のマスが見つかりませんでした")
        var scrolls = 0
        while !redCell.isHittable && scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        redCell.tap()
        XCTAssertTrue(app.staticTexts["柴犬・赤"].waitForExistence(timeout: 10),
                      "要約が「柴犬・赤」になりませんでした")
        attachScreenshot("flow10-breed-setting")

        // 後片付け（ベストエフォート）：チップの種類を「頭文字」に戻す。
        // 後続テストはこの設定に依存しない（フローは test10 が最後で、撮影テストは
        // 起動引数で上書きする）ため、戻し自体は失敗させない（フロー5の後片付けと同方針）。
        // 行が画面下端に半分出た状態では exists/hittable でもタップが効かない
        // （CI #72・#73：行の中心が画面外でメニューが開かなかった）ので、
        // 画面下端に余裕ができる位置までスクロールしてからタップする
        let window = app.windows.firstMatch
        var pickerScrolls = 0
        while chipPicker.exists
                && chipPicker.frame.maxY > window.frame.maxY - 80
                && pickerScrolls < 8 {
            app.swipeUp()
            pickerScrolls += 1
        }
        if chipPicker.isHittable {
            chipPicker.tap()
            let initialItem = app.buttons["頭文字"]
            if initialItem.waitForExistence(timeout: 10) {
                initialItem.tap()
            }
        }
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 10),
                      "カレンダーに戻れませんでした")
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

    /// 要素の value が期待文字列と一致するまで短くポーリングする
    /// （日本語入力の確定が遅れて値へ反映されるまでの猶予。時間切れなら false）。
    private func waitForTextValue(of element: XCUIElement, toEqual expected: String,
                                  timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return (element.value as? String) == expected
    }

    /// 日別シートの予定行を部分スワイプし、削除範囲ダイアログの
    /// 「この回だけ削除」を押すところまで進める共通処理（フロー7・フロー8）。
    ///
    /// 行の特定とスワイプは、行内のテキスト要素（StaticText）の座標に寄せる。
    /// セル要素のラベルには犬名が含まれず、cells のラベル検索では行を掴め
    /// なかったため（CI #39）。座標は要素の frame と app.frame から絶対座標で
    /// 計算する：開始＝要素の中心、終了＝同じ高さでウィンドウ幅の約40%左。
    /// 要素基準の正規化オフセットだと行幅に引きずられて移動量が変わるのと、
    /// フルスワイプ相当になって範囲ダイアログへ直行するのを避けるため
    /// （swipeLeft() は量を制御できないので使わない）。
    private func swipeDayPlanRowAndDeleteOccurrence(rowText: XCUIElement,
                                                    evidenceName: String) {
        XCTAssertTrue(rowText.waitForExistence(timeout: 10),
                      "削除対象の予定行が見つかりませんでした")

        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let rowFrame = rowText.frame
        let swipeStart = origin.withOffset(
            CGVector(dx: rowFrame.midX, dy: rowFrame.midY))
        let swipeEnd = origin.withOffset(
            CGVector(dx: rowFrame.midX - app.frame.width * 0.4, dy: rowFrame.midY))
        swipeStart.press(forDuration: 0.1, thenDragTo: swipeEnd)

        // スワイプ後の到達先は2通りある：OSの削除ボタンが出るか、
        // フルスワイプ扱いで削除範囲のダイアログへ直行するか。
        // どちらに着いたかを1つの待機予算（10秒）で判定し、
        // ボタンが出ていればタップしてダイアログへ進む。
        // 削除ボタンの表記はOS側の言語で変わるため日英両方を見る
        // （ロケール固定で日本語になる想定だが、効かない環境への保険）。
        let swipeDelete = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["削除", "Delete"])).firstMatch
        let deleteOccurrence = app.buttons["この回だけ削除"]
        let deadline = Date().addingTimeInterval(10)
        var reached = deleteOccurrence.exists
        while !reached && Date() < deadline {
            if deleteOccurrence.exists {
                reached = true
            } else if swipeDelete.exists && swipeDelete.isHittable {
                swipeDelete.tap()
                reached = true
            } else {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        if !reached {
            attachFailureEvidence(evidenceName, element: rowText)
            XCTFail("スワイプ後に削除ボタンも削除範囲のダイアログも出ませんでした")
        }
        XCTAssertTrue(deleteOccurrence.waitForExistence(timeout: 10),
                      "削除範囲のダイアログが出ませんでした")
        deleteOccurrence.tap()
        // 診断（CI #40：フロー8で「この回だけ削除」タップ直後にアプリが
        // 存在しなくなった件の切り分け）：削除の反映（ストア更新→一覧の
        // 再描画）が走った直後のアプリ状態を、状態値つき添付で確認する。
        // ここで落ちていれば、呼び出し側の後段の要素待ちが空振りして
        // 失敗箇所がずれる前に、この地点で切り分けられる。
        // フロー7・8の共通処理内に入れてある（フロー7の検証内容は不変で、
        // 生存確認の追加のみ）。
        assertAppRunningForeground("\(evidenceName)-after-delete-tap")
    }

    // MARK: - 診断ヘルパー（アプリ状態）

    /// アプリの実行状態を人間可読な文字列にする（診断添付・失敗文言用）
    private func appStateDescription(_ state: XCUIApplication.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        default: return "その他(rawValue: \(state.rawValue))"
        }
    }

    /// アプリが画面を返せる状態（前面／背面で実行中）かどうか。
    /// 終了済み・状態不明の時に screenshot() や debugDescription を触ると
    /// 「アプリが存在しない」系のエラーになり、本来の失敗を上書きして
    /// しまう（CI #40 のフロー8がその形で表面化した）。証拠系ヘルパーは
    /// まずここで判定してから撮影・取得に進む。
    private var isAppRunning: Bool {
        app.state == .runningForeground || app.state == .runningBackground
    }

    /// アプリの現在状態をテキスト添付として残す
    /// （スクリーンショットに依存しない、アプリ終了時でも残せる証拠）。
    private func attachAppState(_ name: String) {
        let attachment = XCTAttachment(
            string: "アプリ状態: \(appStateDescription(app.state))")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// アプリが前面で動いていることを確認する診断 assertion。
    /// 状態が安定するまで短く待ってから判定し、状態値を添付に残す。
    /// 動いていなければその場で失敗させ、後続の要素待ちが空振りして
    /// 本当の異常発生地点を上書きしないようにする。
    private func assertAppRunningForeground(_ checkpoint: String) {
        let deadline = Date().addingTimeInterval(2)
        var state = app.state
        while state != .runningForeground && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            state = app.state
        }
        attachAppState("\(checkpoint)-app-state")
        XCTAssertEqual(state, .runningForeground,
                       "\(checkpoint)：アプリが前面で実行中ではありません"
                       + "（状態：\(appStateDescription(state))）")
    }

    /// 失敗時点の証拠を残す：画面のスクリーンショット（keepAlways）と、
    /// アプリ全体＋止まった対象要素の debugDescription（テキスト添付）。
    /// 成功時の節目撮影（attachScreenshot）と違い、失敗が確定した箇所からだけ呼ぶ。
    /// アプリが実行中でない場合は、撮影・debugDescription の取得自体が
    /// エラーになって本来の失敗を上書きするため、状態のテキスト添付に
    /// 切り替える（CI #40 のフロー8対策）。
    private func attachFailureEvidence(_ name: String, element: XCUIElement? = nil) {
        guard isAppRunning else {
            let stateNote = XCTAttachment(
                string: "アプリが実行中ではないため、スクリーンショットと "
                    + "debugDescription は取得しませんでした。"
                    + "アプリ状態：\(appStateDescription(app.state))")
            stateNote.name = "\(name)-app-state"
            stateNote.lifetime = .keepAlways
            add(stateNote)
            return
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name)-screenshot"
        shot.lifetime = .keepAlways
        add(shot)

        var text = "== app.debugDescription ==\n\(app.debugDescription)"
        if let element {
            text += "\n\n== 対象要素 debugDescription ==\n\(element.debugDescription)"
        }
        let desc = XCTAttachment(string: text)
        desc.name = "\(name)-debugDescription"
        desc.lifetime = .keepAlways
        add(desc)
    }

    /// スクリーンショットをテスト結果へ添付する（合格時も残すため keepAlways）。
    /// アプリが実行中でない場合は撮影を試みず、状態のテキスト添付に
    /// 切り替える（撮影側の例外で本来の失敗を上書きしないため。
    /// アプリの生存そのものは、要所の assertAppRunningForeground が担う）。
    private func attachScreenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        guard isAppRunning else {
            attachAppState("\(name)-app-state-instead-of-screenshot")
            return
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
