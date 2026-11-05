import SwiftUI

@main
struct WanMapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // アプリ全体のアクセントをコーラルに統一（フェーズN）。
                // シートで開く設定・フォーム類にも効かせるためアプリ最上位に置く。
                .tint(WanStyle.coral)
        }
    }
}
