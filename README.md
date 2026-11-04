# iPhoneアプリ（WanMap）土台

Webプロトタイプで固めた仕様を、iPhoneアプリとして実装するための土台コード。

## 構成

- `WanMap/Sources/Models/` — Facility（施設）／Plan（予定）／Friend（友達・ID設計）
- `WanMap/Sources/Data/FacilityStore.swift` — 施設データの3段構え読み込み（配信JSON→キャッシュ→同梱）
- `WanMap/Sources/Location/LocationService.swift` — 現在地と「今ここ」（2時間消去・置き換え・非表示モード・GPS揺らぎ抑制）
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
- カレンダーの実データ連携、年表示、イベント一覧の中身
