import SwiftUI

/// 共有シート拡張の画面（最小限）
/// 共有された文面の冒頭を見せて、「取り込む」か「キャンセル」かだけを選ばせる。
/// ここでは下書き生成も保存もしない。取り込む＝本体への引き渡し予約だけ。
struct ShareImportView: View {
    /// 共有されたテキスト（取れなかった場合は nil）
    let text: String?
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("WanMapに取り込む", systemImage: "doc.on.clipboard")
                .font(.headline)

            if let text {
                Text(String(text.prefix(120)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("アプリを開くと、下書きとして表示されます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("テキストが見つかりませんでした。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("キャンセル", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button("取り込む", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .disabled(text == nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
    }
}
