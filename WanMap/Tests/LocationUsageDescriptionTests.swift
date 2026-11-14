import Foundation
import XCTest

/// 位置情報の許可文言（UsageDescription）が、実バンドルの Info.plist に
/// 入っていることの回帰テスト。
///
/// 経緯（2026-11-14、TestFlight 実機フィードバックで発覚）：
/// 文言を project.yml の settings.base に INFOPLIST_KEY_* 形式で書いていたが、
/// このプロジェクトの Info.plist は info.path の実ファイル方式
/// （GENERATE_INFOPLIST_FILE=NO）のため、その形式は実バンドルへ反映されない。
/// 結果、実機では許可ダイアログ自体が出ず、設定アプリの WanMap にも
/// 「位置情報」の項目が現れず、GPS が一切動かなかった。
/// 文言の正は project.yml の WanMap ターゲットの info.properties。
/// テストはアプリホストで実行されるため、Bundle.main はアプリバンドル
/// （jp.wanmap.app）を指し、infoDictionary が実際の Info.plist を返す。
final class LocationUsageDescriptionTests: XCTestCase {

    func testWhenInUseUsageDescriptionExists() {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
        XCTAssertFalse(value?.isEmpty ?? true,
                       "NSLocationWhenInUseUsageDescription が実バンドルの Info.plist にありません（許可ダイアログが出ません）")
    }

    func testAlwaysUsageDescriptionExists() {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") as? String
        XCTAssertFalse(value?.isEmpty ?? true,
                       "NSLocationAlwaysAndWhenInUseUsageDescription が実バンドルの Info.plist にありません（「常に許可」への格上げができません）")
    }
}
