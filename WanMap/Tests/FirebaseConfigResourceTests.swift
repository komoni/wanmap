import Foundation
import XCTest

/// Firebase 接続設定（GoogleService-Info.plist）同梱の回帰テスト。
///
/// 経緯：フェーズ2（サーバー同期）の基盤として、接続設定ファイルを
/// アプリバンドルへ同梱する（project.yml の sources に
/// buildPhase: resources で登録する方式。事例1）。
/// ファイルが欠けると起動時の FirebaseApp.configure() が落ちるため、
/// 同梱と中身（対象プロジェクト・バンドルIDの一致）をここで守る。
/// テストはアプリホストで実行されるため、Bundle.main はアプリバンドル
/// （jp.wanmap.app）を指す。
final class FirebaseConfigResourceTests: XCTestCase {

    private func loadConfig() throws -> [String: Any] {
        let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist")
        let unwrappedURL = try XCTUnwrap(url,
                                         "GoogleService-Info.plist がアプリバンドルから見つかりませんでした（ファイルリソースが同梱されていない可能性）")
        let data = try Data(contentsOf: unwrappedURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any],
                             "GoogleService-Info.plist を辞書として読み込めませんでした")
    }

    func testFirebaseConfigBundledForWanMapProject() throws {
        let config = try loadConfig()
        XCTAssertEqual(config["PROJECT_ID"] as? String, "wanmap-e4a66",
                       "接続先は Firebase プロジェクト wanmap-e4a66 であるべきです")
        XCTAssertEqual(config["BUNDLE_ID"] as? String, "jp.wanmap.app",
                       "接続設定のバンドルIDがアプリ（jp.wanmap.app）と一致しません")
        let appID = try XCTUnwrap(config["GOOGLE_APP_ID"] as? String,
                                  "GOOGLE_APP_ID がありません")
        XCTAssertFalse(appID.isEmpty, "GOOGLE_APP_ID が空です")
        XCTAssertEqual(config["IS_ANALYTICS_ENABLED"] as? Bool, false,
                       "Analytics は無効の前提です（フェーズ0の決定）")
    }
}
