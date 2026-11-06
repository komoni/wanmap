import UIKit
import XCTest

/// ハスキー顔（カレンダーヘッダー表示用）のファイルリソース同梱の回帰テスト。
///
/// 経緯：当初ヘッダーはアセットカタログ経由（Image("HuskyFace")）で表示して
/// いたが、CI #50 で「レイアウト幅だけ確保して描画されない」事象が発生した。
/// 切り分けプローブ（旧 HuskyFaceAssetProbeTests）を CI #51 で実行したところ、
/// アプリホスト内で UIImage(named: "HuskyFace") が nil を返し、カタログ経由の
/// 名前解決がアプリ内で機能していないことが判明した。
/// そのためヘッダーの読込は、プレーンなファイルリソース経路
/// （Resources/husky-face.png を Bundle.main.url(forResource:) で引き、
/// UIImage(contentsOfFile:) で読み込む。CalendarView の実装）へ切り替えた。
/// このテストは、その「実際に使われている経路」が壊れていないことを守る
/// 回帰ガードであり、カタログ経由の検証はもう行わない。
/// テストはアプリホストで実行されるため、Bundle.main はアプリバンドル
/// （jp.wanmap.app）を指す。
final class HuskyFaceResourceTests: XCTestCase {

    func testHuskyFaceFileResourceLoadsFromAppBundle() {
        let url = Bundle.main.url(forResource: "husky-face", withExtension: "png")
        XCTAssertNotNil(url,
                        "husky-face.png がアプリバンドルから見つかりませんでした（ファイルリソースが同梱されていない可能性）")
        guard let url else { return }

        let image = UIImage(contentsOfFile: url.path)
        XCTAssertNotNil(image,
                        "husky-face.png を UIImage として読み込めませんでした")
        guard let image else { return }
        XCTAssertGreaterThanOrEqual(image.size.width, 100,
                                    "husky-face の幅が想定より小さいです")
        XCTAssertGreaterThanOrEqual(image.size.height, 100,
                                    "husky-face の高さが想定より小さいです")
    }
}
