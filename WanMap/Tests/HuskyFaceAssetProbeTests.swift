import UIKit
import XCTest

/// アセットカタログ HuskyFace の同梱プローブ（切り分け専用の単体テスト）。
///
/// CI #50 で、カレンダーヘッダーの Image("HuskyFace") がレイアウト幅だけ
/// 確保して描画されない事象があった。このテストは「アセットカタログが
/// アプリバンドルに正しく入っているか」を切り分けるための材料：
/// - 落ちる → カタログ（またはコンパイル済みアセット）自体がバンドルに無い
/// - 通る → カタログは正常で、問題はカタログ経由の描画側にあったと言える
/// テストはアプリホストで実行されるため、UIImage(named:) は
/// アプリバンドル（jp.wanmap.app）を検索する。
final class HuskyFaceAssetProbeTests: XCTestCase {

    func testProbe_huskyFaceAssetCatalogImageLoadsFromAppBundle() {
        let image = UIImage(named: "HuskyFace")
        XCTAssertNotNil(image,
                        "HuskyFace がアプリバンドルから読めませんでした（アセットカタログが同梱されていない可能性）")
        guard let image else { return }
        XCTAssertGreaterThan(image.size.width, 0,
                             "HuskyFace の幅が 0 です")
        XCTAssertGreaterThan(image.size.height, 0,
                             "HuskyFace の高さが 0 です")
    }
}
