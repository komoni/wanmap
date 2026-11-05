import SwiftUI

/// WanMap 共通カラートークン（フェーズN：「可愛い全面」デザインパターン）
/// 色値は codex-design-2026-11-05/patterns-notes.md のパターン2「可愛さ全面」の
/// HEX を正とする。画面側に直書きの色を増やさず、ここを経由する。
enum WanStyle {
    /// 画面背景：ミルク
    static let canvas = Color(hex: 0xFFF8EF)
    /// セル・カード面：クリームホワイト
    static let card = Color(hex: 0xFFFEFC)
    /// 主操作・今日・選択状態・日曜：コーラル
    static let coral = Color(hex: 0xEE7869)
    /// バナー・装飾：アプリコット
    static let apricot = Color(hex: 0xFFC879)
    /// 予定チップ・補助面：パウダーラベンダー
    static let lavender = Color(hex: 0xDCD5F2)
    /// 本文・クラスター：ココア
    static let cocoa = Color(hex: 0x533E38)
    /// 土曜：ソフトブルー
    static let saturday = Color(hex: 0x709DC6)
}

extension Color {
    /// 0xRRGGBB 形式の16進値から不透明色を作る
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
