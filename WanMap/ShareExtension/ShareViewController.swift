import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// 共有シート拡張の入口（NSExtensionPrincipalClass）
///
/// やることは受け渡しだけ：
/// - 共有された添付（テキスト／URL）から文字列を取り出す
/// - 「取り込む」が押されたら App Groups の共有置き場（SharedImportInbox）に保留として置き、拡張を閉じる
/// - 下書き生成（StoryTextParser）・予定の保存は本体側の責務で、ここでは一切しない
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { @MainActor in
            let text = await Self.collectText(from: extensionContext)
            showImportView(text: text)
        }
    }

    private func showImportView(text: String?) {
        let root = ShareImportView(
            text: text,
            onImport: { [weak self] in
                if let text { SharedImportInbox.save(text: text) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                let error = NSError(domain: "jp.wanmap.share", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: "キャンセルしました"])
                self?.extensionContext?.cancelRequest(withError: error)
            })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// 共有アイテムの添付からテキストを取り出してつなげる。
    /// URL はそのまま文字列化して含める（投稿リンク付きの共有に対応）。
    private static func collectText(from context: NSExtensionContext?) async -> String? {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return nil }
        var parts: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadString(from: provider, typeIdentifier: UTType.plainText.identifier) {
                    parts.append(text)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let text = await loadString(from: provider, typeIdentifier: UTType.url.identifier) {
                    parts.append(text)
                }
            }
        }
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// NSItemProvider の completion handler 形式を async に包む。
    /// 返ってくる型は共有元アプリ次第なので、文字列化できるものだけ拾う。
    private static func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                switch item {
                case let text as String:
                    continuation.resume(returning: text)
                case let url as URL:
                    continuation.resume(returning: url.absoluteString)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                case let attributed as NSAttributedString:
                    continuation.resume(returning: attributed.string)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
