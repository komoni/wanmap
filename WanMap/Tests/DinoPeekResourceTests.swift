import UIKit
import XCTest

/// 恐竜ハスキー（カレンダー装飾フッター用）のファイルリソース同梱の回帰テスト。
/// ヘッダーの顔（HuskyFaceResourceTests）と同じ経路
/// （Resources/husky-dino-peek.png を Bundle.main.url(forResource:) で引き、
/// UIImage(contentsOfFile:) で読み込む。DecorationFooterView の実装）を守る。
/// XcodeGen の resources: 無視問題（2026-11-07に原因確定）の再発検出も兼ねる。
final class DinoPeekResourceTests: XCTestCase {

    func testDinoPeekFileResourceLoadsFromAppBundle() {
        let url = Bundle.main.url(forResource: "husky-dino-peek", withExtension: "png")
        XCTAssertNotNil(url,
                        "husky-dino-peek.png がアプリバンドルから見つかりませんでした（ファイルリソースが同梱されていない可能性）")
        guard let url else { return }

        let image = UIImage(contentsOfFile: url.path)
        XCTAssertNotNil(image,
                        "husky-dino-peek.png を UIImage として読み込めませんでした")
        guard let image else { return }
        XCTAssertGreaterThanOrEqual(image.size.width, 300,
                                    "husky-dino-peek の幅が想定より小さいです")
        XCTAssertGreaterThanOrEqual(image.size.height, 300,
                                    "husky-dino-peek の高さが想定より小さいです")
    }
}
