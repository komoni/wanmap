import CoreGraphics
import XCTest
@testable import WanMap

/// 装飾フッターのレイアウト計算（デザイン第二弾）の検証。
/// 「セルを潰さない（最小高さ確保が先、装飾は余りだけ）」と
/// 「スラック量での3段階縮退」が崩れていないことを守る。
final class MonthDecorationLayoutTests: XCTestCase {

    // 既定パラメータ：5週・行間6・フッター間隔6・最小行高76 → 最小グリッド高 = 5*76+4*6 = 404
    private func layout(height: CGFloat, weeks: Int = 5) -> MonthDecorationLayout {
        MonthDecorationLayout.compute(availableHeight: height,
                                      weeks: weeks,
                                      rowSpacing: 6,
                                      footerSpacing: 6,
                                      minRowHeight: 76)
    }

    func testFull_余裕が大きいと犬と波でフッターは上限まで() {
        let l = layout(height: 600)
        XCTAssertEqual(l.stage, .full)
        XCTAssertEqual(l.footerHeight, 104)
        // グリッド = 600-104-6 = 490、行高 = (490-24)/5 = 93.2（最小76以上）
        XCTAssertEqual(l.rowHeight, 93.2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(l.rowHeight, 76)
    }

    func testFull_境界ではフッターを入れても行高が最小ちょうどになる() {
        // スラック94（=しきい値）→ フッター88、グリッドは最小構成ぴったり
        let l = layout(height: 404 + 94)
        XCTAssertEqual(l.stage, .full)
        XCTAssertEqual(l.footerHeight, 88)
        XCTAssertEqual(l.rowHeight, 76, accuracy: 0.001)
    }

    func testWaveOnly_中くらいの余裕では波だけ() {
        // スラック30（=しきい値）→ 波24、行高は最小ちょうど
        let l = layout(height: 404 + 30)
        XCTAssertEqual(l.stage, .waveOnly)
        XCTAssertEqual(l.footerHeight, 24)
        XCTAssertEqual(l.rowHeight, 76, accuracy: 0.001)
    }

    func testNone_余裕がなければ装飾なしで行高は最小を維持() {
        let l = layout(height: 404)
        XCTAssertEqual(l.stage, .none)
        XCTAssertEqual(l.footerHeight, 0)
        XCTAssertEqual(l.rowHeight, 76, accuracy: 0.001)
    }

    func testNone_6週で高さ不足なら装飾なしでセルを詰めて収める() {
        // 6週の最小構成は 6*76+5*6 = 486。430しかない場合は装飾なし・行高は詰まる
        let l = layout(height: 430, weeks: 6)
        XCTAssertEqual(l.stage, .none)
        XCTAssertEqual(l.footerHeight, 0)
        XCTAssertEqual(l.rowHeight, (430 - 30) / 6, accuracy: 0.001)
    }

    func testFull_6週でも余裕があれば犬と波が出る() {
        let l = layout(height: 700, weeks: 6)
        XCTAssertEqual(l.stage, .full)
        XCTAssertEqual(l.footerHeight, 104)
        XCTAssertGreaterThanOrEqual(l.rowHeight, 76)
    }
}
