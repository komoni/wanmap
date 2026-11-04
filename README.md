# iPhoneアプリ（WanMap）土台

Webプロトタイプで固めた仕様を、iPhoneアプリとして実装するための土台コード。

## 構成

- `WanMap/Sources/Models/` — Facility（施設）／Plan（予定）／Friend（友達・ID設計）
- `WanMap/Sources/Data/FacilityStore.swift` — 施設データの3段構え読み込み（配信JSON→キャッシュ→同梱）
- `WanMap/Sources/Data/PlanStore.swift` — 予定の端末内保存（Documents/plans.json）とCRUD、「今ここ」の保持（isPresence の予定として保存、2時間除外・移動で置き換え）、犬の名前の使い回し
- `WanMap/Sources/Data/FriendStore.swift` — 友達データの端末内保存（Documents/friends.json）。自分のID（表示ID／内部ID）、ID検索・申請（モック：自動承認）、受信申請の承認・拒否、「見せない」リスト。実通信はまだ無い
- `WanMap/Sources/Data/SeedData.swift` — 仮想ユーザーの予定データ（DEBUG専用、プレビュー／検証用）
- `WanMap/Sources/Location/LocationService.swift` — 現在地の取得（非表示モード・GPS揺らぎ抑制）
- `WanMap/Sources/Views/` — RootView（カレンダー／地図／イベントのタブ）、CalendarView、DogMapView（＋施設シート、日付ストリップ＋時間帯での予定絞り込み、友達レール、施設検索、予定アイコンの浮遊＋指から逃げる動き）、InfoBannerView（広告／イベント告知バナー。地図・カレンダーの上部に共通の枠）、FriendsView（友達モック：ID表示・検索・申請・QR生成とコード追加）、SettingsView（自分のID、見せない相手＝友達画面と連動、位置情報の説明、データリセット）。友達画面と設定画面はカレンダー／地図の両方からアイコンボタンで開ける
- `WanMap/project.yml` — XcodeGen 用の定義。施設JSONは `WanMap/Resources/facilities.json` に置く
  （最新の書き出しは `../facility-data/facilities.json`、620件）
- `.github/workflows/build.yml` — GitHub Actions（macOS）で署名なしビルド検証するCI
- `DATA_UPDATE_DESIGN.md` — 施設データをアプリ再審査なしで更新する仕組みの設計
- 利用ライブラリ：ClusterMap 3.0.0（https://github.com/vospennikov/ClusterMap、MIT License、SPMで導入）— 地図の施設マーカーのクラスタリング計算（`DogMapView` の施設表示を差分描画にしている。予定アイコンは対象外）

## ビルド方法

1. 本人のMac：XcodeGen を入れて `WanMap/` で `xcodegen generate` → Xcodeで開く
2. クラウド：このフォルダをGitHubリポジトリにpushすれば、Actionsが自動でビルド検証する

## 未実装（これから詰める）

- アカウント基盤（Sign in with Apple／Instagram連携ログイン）とサーバー同期
- 友達機能の実通信（モックUIは実装済み。申請・承認・通知の実通信）とQR実カメラ読み取り（現状はコード手入力で追加）
- バックグラウンド位置（許可フローと審査対応含む）
- 施設連携（施設オーナーのInstagram投稿→下書き→確認公開）
- イベント募集への参加・承認機能（イベント一覧の表示自体は実装済み）
- 予定データのサーバー同期（現状は端末内保存のみ）
