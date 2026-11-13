import Foundation
import XCTest

/// プライバシーマニフェスト（PrivacyInfo.xcprivacy）同梱の回帰テスト。
///
/// 経緯：UserDefaults は Required Reason API のため、申請時にプライバシー
/// マニフェストでの理由宣言が必須（APPLE_COMPLIANCE.md のギャップ2）。
/// リソースは project.yml の sources に buildPhase: resources で登録する
/// 方式がこのリポジトリの正（resources: は XcodeGen が無視する。事例1）。
/// このテストは、その経路でファイルがアプリバンドルへ同梱され、
/// 宣言内容（トラッキングなし／UserDefaults の理由 CA92.1）が
/// 欠けていないことを守る。
/// テストはアプリホストで実行されるため、Bundle.main はアプリバンドル
/// （jp.wanmap.app）を指す。
final class PrivacyInfoResourceTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        let url = Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        let unwrappedURL = try XCTUnwrap(url,
                                         "PrivacyInfo.xcprivacy がアプリバンドルから見つかりませんでした（ファイルリソースが同梱されていない可能性）")
        let data = try Data(contentsOf: unwrappedURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any],
                             "PrivacyInfo.xcprivacy を辞書として読み込めませんでした")
    }

    func testPrivacyInfoBundledAndDeclaresNoTracking() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false,
                       "NSPrivacyTracking は false（トラッキングなし）であるべきです")
    }

    func testPrivacyInfoDeclaresUserDefaultsReason() throws {
        let manifest = try loadManifest()
        let apiTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
                                     "NSPrivacyAccessedAPITypes がありません")
        let userDefaults = apiTypes.first { ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults" }
        let entry = try XCTUnwrap(userDefaults,
                                  "UserDefaults の Accessed API 宣言がありません")
        let reasons = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String],
                                    "UserDefaults の理由コードがありません")
        XCTAssertTrue(reasons.contains("CA92.1"),
                      "UserDefaults の理由コード CA92.1 が宣言されていません")
    }
}
