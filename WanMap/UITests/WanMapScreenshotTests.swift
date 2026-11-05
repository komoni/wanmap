import XCTest

/// 画面撮影用のUIテスト
///
/// 目的：実機（TestFlight）前に、クラウドMac上のシミュレータで実際のアプリ画面を
/// 撮影し、本人が目で見て確認できるようにすること。
/// 起動引数 -UITestingSeedData を付けて起動すると、仮想ユーザーのシード予定
/// （ソラ／ハル／モモ／コタロウ／ムギ／レオ、ドッグウィズ定例など）が表示された
/// 状態になる（RootView の DEBUG 専用分岐。実データには混ざらない）。
/// 撮影は XCTAttachment（lifetime = .keepAlways）に残し、CI が .xcresult から
/// 画像を取り出してアーティファクト（wanmap-screenshots）にする。
///
/// 対象外：施設シートの撮影。地図上のマーカーのタップは座標依存で不安定なため、
/// あえて撮らない（シート自体の確認は TestFlight 実機で行う）。
final class WanMapScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    /// 割り込みモニタのトークン（テスト中保持しておく）
    private var interruptionMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-UITestingSeedData"]

        // 起動直後（RootView の .task → 位置情報リクエスト）に出る
        // システムの許可アラートを捌く。シミュレータの表示言語が
        // 英語／日本語どちらでも拾えるよう両方の表記を見る。
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

    // MARK: - 撮影対象の画面

    /// ① カレンダー（月表示・起動直後）
    func test01_calendarMonth() throws {
        launchAndSettleOnCalendar()
        attachScreenshot("01-calendar-month")
    }

    /// ② 地図タブ
    func test02_map() throws {
        launchAndSettleOnCalendar()
        app.tabBars.buttons["地図"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15),
                      "地図が表示されませんでした")
        // タイルとマーカーの描画が落ち着くまで待ってから撮る
        Thread.sleep(forTimeInterval: 4)
        attachScreenshot("02-map")
    }

    /// ③ イベントタブ
    func test03_events() throws {
        launchAndSettleOnCalendar()
        app.tabBars.buttons["イベント"].tap()
        // イベント一覧にはシードの募集（ドッグウィズ）が並ぶ
        XCTAssertTrue(app.staticTexts["ドッグウィズ"].waitForExistence(timeout: 15),
                      "イベント一覧にシードの募集が表示されませんでした")
        attachScreenshot("03-events")
    }

    /// ④ カレンダーで予定のある日をタップした日別予定
    func test04_dayPlans() throws {
        launchAndSettleOnCalendar()
        // シードでは「今日」と「直近の土曜」のセルに SKドッグラン が出る。どちらでもよい。
        // セル内では場所名が「SK...」のように省略表示されるため、完全一致ではなく
        // 前方一致で探す（省略表示でも省略されていないラベルでも拾える）。
        let planText = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'SK'")).firstMatch
        XCTAssertTrue(planText.waitForExistence(timeout: 15),
                      "予定のある日のセル（SKドッグラン）が見つかりませんでした")
        // 小さいキャプション文字でヒット可能と判定されない場合は、中心座標でタップする
        if planText.isHittable {
            planText.tap()
        } else {
            planText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        // 日別予定シートのタイトルは「M月d日（E）」形式（例：11月5日（水））。
        // ナビゲーションバーの label 属性での照合は実装依存で不安定なため、
        // タイトル文字列そのもので待つ。「月」と「日」を両方含むテキストは
        // カレンダー画面側には無い（年タイトルは「2026年11月」で「日」を含まず、
        // バナーは「11/8（日）」で「月」を含まない）ので、シート出現の判定に使える。
        let dayTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '月' AND label CONTAINS '日'")).firstMatch
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 15),
                      "日別予定シートが開きませんでした")
        attachScreenshot("04-day-plans")
    }

    /// ⑤ 設定画面（カレンダーの歯車ボタンから）
    func test05_settings() throws {
        launchAndSettleOnCalendar()
        let settingsButton = app.buttons["calendarSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15),
                      "設定ボタンが見つかりませんでした")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15),
                      "設定画面が開きませんでした")
        attachScreenshot("05-settings")
    }

    // MARK: - 共通処理

    /// シード付きで起動し、位置情報アラートを捌いてカレンダー表示で落ち着かせる
    private func launchAndSettleOnCalendar() {
        app.launch()

        let calendarTab = app.tabBars.buttons["カレンダー"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 30),
                      "タブバーが表示されませんでした")
        // 位置情報アラートが出るなら、このタップ試行のタイミングで
        // 割り込みモニタが処理する（既に選択中のタブなので、素通りしても無害）
        Thread.sleep(forTimeInterval: 2)
        calendarTab.tap()

        XCTAssertTrue(app.buttons["今日"].waitForExistence(timeout: 15),
                      "カレンダー画面が表示されませんでした")
        // バナー切り替わりやレイアウトが落ち着いてから撮る
        Thread.sleep(forTimeInterval: 1)
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
