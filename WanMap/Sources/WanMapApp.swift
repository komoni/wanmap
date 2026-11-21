import FirebaseCore
import SwiftUI

@main
struct WanMapApp: App {
    init() {
        // Firebase の初期化（フェーズ2、2026-11-21）。接続設定は
        // Resources/GoogleService-Info.plist（同梱）から読まれる。
        // ここでは初期化までで、サインインや同期は後続の単位で組み込む
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // アプリ全体のアクセントをコーラルに統一（フェーズN）。
                // シートで開く設定・フォーム類にも効かせるためアプリ最上位に置く。
                .tint(WanStyle.coral)
        }
    }
}
