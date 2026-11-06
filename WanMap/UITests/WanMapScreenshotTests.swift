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
        // ロケールも日本語に固定し、撮影画面の表記をCI環境に左右されないようにする
        app.launchArguments += ["-UITestingSeedData",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]

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

    // MARK: - デザイン・気持ちよさ第一弾の比較撮影
    // 配色案（コーラル／ココア）とヘッダー段数は起動引数で確定的に切り替える
    // （RootView の DEBUG 分岐 → AppearanceStore の引数優先）。本人が見比べて選ぶための撮影。

    /// ⑥ カレンダー：配色案A（コーラル）
    func test06_designCalendarCoral() throws {
        app.launchArguments += ["-wmButtonVariant", "coral"]
        launchAndSettleOnCalendar()
        assertHeaderElementsInsideWindow("1段・コーラル")
        assertHuskyImageVisible("1段・コーラル")
        attachScreenshot("design-calendar-coral")
    }

    /// ⑦ カレンダー：配色案B（ココア）
    func test07_designCalendarCocoa() throws {
        app.launchArguments += ["-wmButtonVariant", "cocoa"]
        launchAndSettleOnCalendar()
        assertHeaderElementsInsideWindow("1段・ココア")
        assertHuskyImageVisible("1段・ココア")
        attachScreenshot("design-calendar-cocoa")
    }

    /// ⑧ カレンダー：ヘッダー2段レイアウト（配色は案A）
    func test08_designCalendarStacked() throws {
        app.launchArguments += ["-wmHeaderLayout", "stacked"]
        launchAndSettleOnCalendar()
        assertHeaderElementsInsideWindow("2段")
        assertHuskyImageVisible("2段")
        attachScreenshot("design-calendar-stacked")
    }

    /// ⑨ 設定画面：「見た目」「音と触覚」セクションが見える位置までスクロールして撮影
    func test09_designSettings() throws {
        app.launchArguments += ["-wmButtonVariant", "cocoa"]
        launchAndSettleOnCalendar()
        let settingsButton = app.buttons["calendarSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15),
                      "設定ボタンが見つかりませんでした")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15),
                      "設定画面が開きませんでした")
        // 「音と触覚」セクションの「効果を試す」が出るまでリストをスクロールする
        let previewButton = app.buttons["効果を試す"]
        var attempts = 0
        while !previewButton.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(previewButton.exists,
                      "設定の「効果を試す」ボタンが見つかりませんでした")
        attachScreenshot("design-settings")
    }

    // MARK: - 共通処理

    /// ヘッダー要素が画面（window）の内側に収まっていることの回帰ガード。
    /// CI #49 で、1段では今日ボタンが左端で切れ設定ボタンが画面外へ出て、
    /// 両レイアウトでタイトルが省略されハスキー顔が幅0に潰れる崩れがあった。
    /// タイトルの省略（「202…」）自体はラベルでは検出できないため、
    /// フレームの収まり＋タイトル幅の下限で「押し出し・圧縮」を検出し、
    /// 全文表示そのものは目視スクショで担保する。
    private func assertHeaderElementsInsideWindow(_ layout: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10),
                      "windowが見つかりませんでした")
        // 座標の丸め誤差を1ptだけ許容する
        let bounds = window.frame.insetBy(dx: -1, dy: -1)

        func assertInside(_ element: XCUIElement, _ name: String) {
            XCTAssertTrue(element.waitForExistence(timeout: 10),
                          "\(name)が見つかりませんでした（\(layout)）")
            XCTAssertTrue(bounds.contains(element.frame),
                          "\(name)が画面外にはみ出しています（\(layout)）: \(element.frame)")
        }

        assertInside(app.buttons["今日"], "今日ボタン")
        assertInside(app.buttons["calendarPrevMonthButton"], "前月ボタン")
        assertInside(app.buttons["calendarNextMonthButton"], "次月ボタン")
        assertInside(app.buttons["calendarSettingsButton"], "設定ボタン")

        // 年月タイトル（例「2026年11月」）。カレンダー画面で「年」と「月」を
        // 両方含む静的テキストはタイトルだけ（日セルは数字、バナーは「11/8（日）」等）
        let title = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '年' AND label CONTAINS '月'")).firstMatch
        assertInside(title, "年月タイトル")
        // 全文は 1段（subheadline）でも約75ptある。潰れて省略されると
        // 40〜60pt台まで縮むため、幅の下限でも圧縮を検出する
        XCTAssertGreaterThan(title.frame.width, 60,
                             "年月タイトルが圧縮されている可能性があります（\(layout)）: 幅 \(title.frame.width)")
    }

    /// ハスキー顔が実際に要素として存在し、幅を持って window 内に
    /// 収まっていることの回帰ガード。CI #50 で、カタログ経由の画像が
    /// レイアウト幅だけ確保して無描画になる事象があったため、
    /// 識別子 calendarHuskyImage のフレーム幅（20pt以上）と
    /// window 内収まりを撮影前に assert する。
    private func assertHuskyImageVisible(_ layout: String) {
        let husky = app.images["calendarHuskyImage"]
        XCTAssertTrue(husky.waitForExistence(timeout: 10),
                      "ハスキー顔が見つかりませんでした（\(layout)）")
        XCTAssertGreaterThanOrEqual(husky.frame.width, 20,
                                    "ハスキー顔の幅が小さすぎます（\(layout)）: \(husky.frame.width)")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10),
                      "windowが見つかりませんでした")
        // 座標の丸め誤差を1ptだけ許容する
        let bounds = window.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(bounds.contains(husky.frame),
                      "ハスキー顔が画面外にはみ出しています（\(layout)）: \(husky.frame)")
    }

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
