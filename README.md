# iPhoneアプリ（WanMap）土台

Webプロトタイプで固めた仕様を、iPhoneアプリとして実装するための土台コード。

## 構成

- `WanMap/Sources/Models/` — Facility（施設）／Plan（予定）／Friend（友達・ID設計）
- `WanMap/Sources/Data/FacilityStore.swift` — 施設データの3段構え読み込み（配信JSON→キャッシュ→同梱）
- `WanMap/Sources/Data/PlanStore.swift` — 予定の端末内保存（Documents/plans.json）とCRUD、「今ここ」の保持（isPresence の予定として保存、2時間除外・移動で置き換え）、犬の名前の使い回し
- `WanMap/Sources/Data/SeedData.swift` — 仮想ユーザーの予定データ（DEBUG専用、プレビュー／検証用）
- `WanMap/Sources/Location/LocationService.swift` — 現在地の取得（非表示モード・GPS揺らぎ抑制）
- `WanMap/Sources/Views/` — RootView（カレンダー／地図／イベントのタブ）、CalendarView、DogMapView（＋施設シート）
- `WanMap/project.yml` — XcodeGen 用の定義。施設JSONは `WanMap/Resources/facilities.json` に置く
  （最新の書き出しは `../facility-data/facilities.json`、620件）
- `.github/workflows/build.yml` — GitHub Actions（macOS）で署名なしビルド検証するCI
- `DATA_UPDATE_DESIGN.md` — 施設データをアプリ再審査なしで更新する仕組みの設計

## ビルド方法

1. 本人のMac：XcodeGen を入れて `WanMap/` で `xcodegen generate` → Xcodeで開く
2. クラウド：このフォルダをGitHubリポジトリにpushすれば、Actionsが自動でビルド検証する

## 未実装（これから詰める）

- アカウント基盤（Sign in with Apple／Instagram連携ログイン）とサーバー同期
- 友達機能の実通信（申請・承認・通知）とQR実カメラ読み取り
- バックグラウンド位置（許可フローと審査対応含む）
- 施設連携（施設オーナーのInstagram投稿→下書き→確認公開）
- イベント募集への参加・承認機能（イベント一覧の表示自体は実装済み）
- 予定データのサーバー同期（現状は端末内保存のみ）
