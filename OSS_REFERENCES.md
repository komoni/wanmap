# 参考にする既存コード（GitHub調査：2026-11-03確認）

## 地図（SwiftUI + MapKit）

- **ClusterMap**（https://github.com/vospennikov/ClusterMap、MIT、⭐約125）
  QuadTree＋actorの `ClusterManager` で差分だけを適用する設計が、施設620件＋友達アイコンの更新に直結する。Example の iOS 17 Map 連携を主に参考にする。
  **フェーズD（2026-11-05）でSPM導入済み**：`project.yml` に `from: 3.0.0` で追加し、`DogMapView` の施設マーカーを ClusterManager 経由の差分描画に切り替えた（対象は施設のみ。予定アイコンと「今ここ」はクラスタリングしない）。
- **Meshtastic-Apple**（https://github.com/meshtastic/Meshtastic-Apple、GPL-3.0、⭐約961）
  製品レベルの地図アプリの全体構成（XcodeGen、多言語、CI）の見本。**GPLのため流用不可・閲覧参考のみ**。

## カレンダー

- **Mijick/CalendarView**（https://github.com/Mijick/CalendarView、MIT、⭐約578）
  純SwiftUIで日セルを全面カスタムできる。パステル＋🐶アイコンのデザインに合わせやすい。年表示は弱いので自前。
- **KVKCalendar**（https://github.com/kvyatkovskys/KVKCalendar、MIT、⭐約807）
  年表示まで揃う。UIKit製なので、年表示のレイアウト設計だけ借りる。

## 施設データの配信（アプリ更新なし差し替え）

- **firebase/quickstart-ios の config/**（https://github.com/firebase/quickstart-ios、Apache-2.0、⭐約3,036）
  Remote Config の fetch→キャッシュ→activate の作法が、版数付きJSON配信の運用の土台になる。データ本体は自前JSON配信でいく（設計は DATA_UPDATE_DESIGN.md）。
- **configcat/swift-sdk**（https://github.com/configcat/swift-sdk、ライセンス要確認、⭐約27）
  CDN取得＋ポーリング＋キャッシュ差し替え可能クラスの具体例。設計参考のみ。

## 位置情報（バックグラウンド・省電力）

- **SwiftLocation**（https://github.com/malcommac/SwiftLocation、MIT、⭐約3,419）
  CLLocationManager の async/await ラッパー。significant location changes（大きな移動のみ）中心に組む。モック付きテストも参考になる。
- Apple公式サンプル「Monitoring location changes with Core Location」（CLMonitor / liveUpdates）はジオフェンスの正典として併読する。

## 認証

- **AppAuth-iOS**（https://github.com/openid/AppAuth-iOS、Apache-2.0、⭐約2,038）
  OAuth 2.0/OIDC の標準実装（PKCE＋ASWebAuthenticationSession）。Instagram連携のアプリ側フローはこれ。トークン交換はサーバー側必須。
- Sign in with Apple は AuthenticationServices 標準。firebase/quickstart-ios の authentication/ で流れを確認。

## 土台コードへの反映方針

- 地図の施設表示更新：ClusterMapの「差分適用」をフェーズDで実装済み（施設マーカーのみ。`ClusterManager.reload` の Difference を表示配列へ反映）
- カレンダー年表示：KVKのレイアウトを参考に自前実装（CalendarView の yearGrid）
- 位置：LocationService は将来 SwiftLocation の significant-changes パターンへ寄せる（常時高精度GPSは使わない）
