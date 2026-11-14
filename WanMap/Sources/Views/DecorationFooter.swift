import SwiftUI
import UIKit

/// カレンダー月グリッド下端の装飾フッターのレイアウト計算（デザイン第二弾）。
///
/// 方針（ちゃぴ設計提案＋むーの検品＋本人の評価で確定）：
/// - 装飾はグリッドの上に重ねず、レイアウト内のフッターとして下に置く。
///   予定セルを潰さないことが最優先で、まずセルの最小高さを確保し、
///   余った高さ（スラック）だけを装飾に回す。
/// - 主役は下部の「ギンガム波帯＋恐竜ハスキー」の融合シーン。
///   上部の装飾（バナーのテープ・四隅の肉球など）は本人が不要と判断したため入れない。
/// - スラック量で3段階に縮退する：犬＋波（full）／波だけ（waveOnly）／なし（none）。
/// - フッターが無い画面（年表示・小さい画面・大きな文字）でもグリッドは壊れず、
///   高さが最小構成にすら足りない場合はセルを少し詰めて収める（装飾は出さない）。
struct MonthDecorationLayout: Equatable {
    enum Stage: Equatable {
        case full      // 恐竜ハスキー＋波帯
        case waveOnly  // 波帯だけ
        case none      // 装飾なし
    }

    var stage: Stage
    /// フッターの高さ（pt）。none の時は 0
    var footerHeight: CGFloat
    /// 週の行1つ分の高さ（pt）
    var rowHeight: CGFloat

    /// 犬＋波のシーンに必要なスラック（フッター間隔込みの下限）。
    /// シーンの下限はフッター64pt＋間隔6pt。実測（CIシミュレータ＝
    /// iPhone 16 Pro級、使える高さ564pt）では6週の月でもスラック78ptが
    /// 残り、フッター72pt・行高は最小76ptのまま犬が出る。
    /// 本人の決定（2026-11-07「6週の月も犬を出す」）を受けた値。
    static let fullSlackThreshold: CGFloat = 70
    /// 波だけに必要なスラック（フッター間隔込みの下限）
    static let waveSlackThreshold: CGFloat = 30
    /// フッター高さの上限
    static let maxFooterHeight: CGFloat = 104
    /// 波だけの時のフッター高さ
    static let waveOnlyHeight: CGFloat = 24

    /// - Parameters:
    ///   - availableHeight: グリッド＋フッターに使える高さ H
    ///   - weeks: その月の週数 R
    ///   - rowSpacing: 週の行間 g
    ///   - footerSpacing: グリッドとフッターの間隔（フッターがある時だけ消費）
    ///   - minRowHeight: セルの最小高さ m（Dynamic Type 込みの呼び出し側で決める）
    static func compute(availableHeight: CGFloat,
                        weeks: Int,
                        rowSpacing: CGFloat,
                        footerSpacing: CGFloat,
                        minRowHeight: CGFloat) -> MonthDecorationLayout {
        guard weeks > 0 else {
            return MonthDecorationLayout(stage: .none, footerHeight: 0, rowHeight: 0)
        }
        let gridMinimum = CGFloat(weeks) * minRowHeight + CGFloat(weeks - 1) * rowSpacing
        let slack = max(0, availableHeight - gridMinimum)

        let stage: Stage
        let footerHeight: CGFloat
        if slack >= fullSlackThreshold {
            stage = .full
            footerHeight = min(slack - footerSpacing, maxFooterHeight)
        } else if slack >= waveSlackThreshold {
            stage = .waveOnly
            footerHeight = waveOnlyHeight
        } else {
            stage = .none
            footerHeight = 0
        }

        let gridHeight = availableHeight - footerHeight - (footerHeight > 0 ? footerSpacing : 0)
        let rowHeight = max(0, (gridHeight - CGFloat(weeks - 1) * rowSpacing) / CGFloat(weeks))
        return MonthDecorationLayout(stage: stage, footerHeight: footerHeight, rowHeight: rowHeight)
    }
}

/// 装飾フッターの見た目。波帯の上に恐竜ハスキーの下部を重ねて
/// 「波から顔を出している」一体感を出す。全体が装飾扱いで、
/// 当たり判定・読み上げの対象にしない。
struct DecorationFooterView: View {
    let stage: MonthDecorationLayout.Stage
    let height: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// まばたき中か（タップで一瞬だけ true になる）
    @State private var blinking = false

    /// 波帯の高さ（フッター下端に敷く）
    private static let waveBandHeight: CGFloat = 26

    /// 恐竜ハスキー。本人が選んだコミカルな画像を切り抜いた透過PNG。
    /// ヘッダーの顔と同じくプレーンなファイルリソース経由で読み込む
    /// （同梱の回帰ガードは DinoPeekResourceTests）。
    /// 読み込めない場合は犬なしで波だけ出す（別画像での誤魔化しはしない）。
    private static let dinoImage: UIImage? = {
        guard let url = Bundle.main.url(forResource: "husky-dino-peek", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            if stage == .full, let dino = Self.dinoImage {
                // 犬はフッター高さより少し大きく置き、下部を波帯に隠して融合させる
                HStack {
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: dino)
                            .resizable()
                            .scaledToFit()
                            .frame(height: height + 12)
                            // タップでまばたき（実機フィードバック第2ラウンド、2026-11-14）。
                            // まぶたは原画の目の位置に合わせた楕円を一瞬だけ被せる
                            .overlay {
                                GeometryReader { geo in
                                    ZStack {
                                        eyelid(in: geo.size, cx: 0.297, cy: 0.418)
                                        eyelid(in: geo.size, cx: 0.442, cy: 0.395)
                                    }
                                    .opacity(blinking ? 1 : 0)
                                }
                            }
                            .onTapGesture { blink() }
                        // モックにあった小さなハートとキラキラ（犬の頭の近くにだけ）
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WanStyle.coral)
                            .offset(x: 2, y: 4)
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundStyle(WanStyle.apricot)
                            .offset(x: -34, y: -2)
                    }
                    .padding(.trailing, 10)
                }
            }
            waveBand
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    /// まばたき用のまぶた：顔の毛色に近いクリームの楕円。
    /// 目の位置は原画（640×562）実測の相対座標（左目／右目）
    private func eyelid(in size: CGSize, cx: CGFloat, cy: CGFloat) -> some View {
        Ellipse()
            .fill(Color(red: 0.96, green: 0.92, blue: 0.83))
            .frame(width: size.width * 0.105, height: size.height * 0.11)
            .position(x: size.width * cx, y: size.height * cy)
    }

    /// タップでまばたきする（閉じて少し置いて開く）。モーション軽減時はしない
    private func blink() {
        guard !blinking, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.06)) { blinking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.09)) { blinking = false }
        }
    }

    /// 下端の波帯：波型に切り抜いたギンガム＋白い肉球1〜2個。
    /// 「透明度を下げる」設定時は柄なしの無地にする。
    private var waveBand: some View {
        ZStack(alignment: .bottom) {
            if reduceTransparency {
                WaveTopShape()
                    .fill(WanStyle.lavender.opacity(0.5))
            } else {
                WaveTopShape()
                    .fill(WanStyle.lavender.opacity(0.30))
                GinghamBand(base: .clear, stripe: WanStyle.lavender, cell: 10, stripeOpacity: 0.35)
                    .clipShape(WaveTopShape())
            }
            // 波の中の肉球（モックの再現。犬に近い右側には置かず、左〜中央だけ）
            HStack {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .rotationEffect(.degrees(-14))
                    .padding(.leading, 26)
                if stage == .full {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .rotationEffect(.degrees(12))
                        .padding(.leading, 54)
                }
                Spacer()
            }
            .padding(.bottom, 5)
        }
        .frame(height: Self.waveBandHeight + 6)
    }
}

/// 上辺がゆるい波になっている帯の形。サイン波を刻んで滑らかにする。
struct WaveTopShape: Shape {
    /// 波の振幅（pt）
    var amplitude: CGFloat = 3.5
    /// 横方向のうねりの数
    var humps: Double = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 72
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            let y = rect.minY + amplitude + (0.5 - 0.5 * cos(t * .pi * 2 * CGFloat(humps))) * amplitude
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
