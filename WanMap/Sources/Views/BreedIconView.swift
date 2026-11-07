import SwiftUI

/// 犬種アイコンの丸表示（設定のプレビュー・毛色グリッド用）
/// アセットが無い場合は肉球のプレースホルダを出す。
struct BreedIconView: View {
    /// アセット名。nil はプレースホルダ
    let asset: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(WanStyle.canvas)
            if let asset, UIImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(WanStyle.cocoa.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(WanStyle.cocoa.opacity(0.25), lineWidth: 1))
    }
}

/// 毛色グリッドの1マス：アイコン＋色名。未制作の色は肉球＋「準備中」で、
/// 「選べない色」と誤解させない（選択自体はできる）。
struct BreedColorCell: View {
    let color: BreedColor
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                BreedIconView(asset: color.icon, size: 52)
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(WanStyle.coral, lineWidth: 3)
                                .frame(width: 56, height: 56)
                        }
                    }
                Text(color.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if color.icon == nil {
                    Text("アイコン準備中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.name)\(color.icon == nil ? "、アイコン準備中" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("breedColor_\(color.id)")
    }
}
