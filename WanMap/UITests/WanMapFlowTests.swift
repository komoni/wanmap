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
