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

// MARK: - 共通の押し心地（デザイン・気持ちよさ第一弾）

/// 押下フィードバックのアニメーション（設計原則メモ 2026-11-10）。
/// 押込みは即応（easeOut 0.08）、戻りは軽いスプリングにして「軽くて気持ちいい」戻りにする。
/// 押下中かどうかで使うアニメーションを切り替える。
func wanPressAnimation(isPressed: Bool) -> Animation {
    isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.25, dampingFraction: 0.80)
}

/// 押下中に少しだけ沈む（scale 0.97）共通ボタン表現。
/// 沈むのは描画だけで、ヒット領域・配置は変えない。
/// 「モーションを減らす」設定時は拡大縮小を行わない。
struct WanPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(wanPressAnimation(isPressed: configuration.isPressed),
                       value: configuration.isPressed)
    }
}

/// 主ボタン（地色＋白文字）の共通表現。地色は AppearanceStore の配色案から渡す。
/// 押下中は沈み＋少し暗くなる。「モーションを減らす」時は拡縮なしで明度だけ変える。
struct WanPrimaryButtonStyle: ButtonStyle {
    var fill: Color
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(wanPressAnimation(isPressed: configuration.isPressed),
                       value: configuration.isPressed)
    }
}

extension View {
    /// アイコンボタンのタップ領域を最小44ptに広げる（見た目の大きさは変えない）
    func wanTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - ギンガムチェック（カレンダーヘッダーの帯だけに敷く淡い柄）

/// ミルク地＋薄いラベンダーのギンガムを Canvas で静的描画する。
/// 縦縞と横縞の重なりでチェックらしく見せる。大きな背景画像は持たない。
/// 装飾なので当たり判定・読み上げの対象にしない。
/// 「透明度を下げる」設定時は呼び出し側で無地に切り替えること。
struct GinghamBand: View {
    var base: Color = WanStyle.card
    var stripe: Color = WanStyle.lavender
    /// 1マスの大きさ（pt）
    var cell: CGFloat = 10
    var stripeOpacity: Double = 0.38

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            context.opacity = stripeOpacity
            var x = CGFloat.zero
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: cell, height: size.height)),
                             with: .color(stripe))
                x += cell * 2
            }
            var y = CGFloat.zero
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: cell)),
                             with: .color(stripe))
                y += cell * 2
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
