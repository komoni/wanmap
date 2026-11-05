# iPhoneアプリ（WanMap）土台

Webプロトタイプで固めた仕様を、iPhoneアプリとして実装するための土台コード。

## 構成

- `WanMap/Sources/Models/` — Facility（施設）／Plan（予定）／Friend（友達・ID設計）／UserPlace（ユーザーが追加した場所）
- `WanMap/Sources/Data/FacilityStore.swift` — 施設データの3段構え読み込み（配信JSON→キャッシュ→同梱）
- `WanMap/Sources/Data/UserPlaceStore.swift` — ユーザーが追加した場所の端末内保存（Documents/user_places.json）とCRUD。公式施設JSONとは分離し、表示・検索の層でのみマージする（ユーザーの情報が優先）。公開範囲のデフォルトは「招待した人だけ」で、共有されるのは場所名のみ
- `WanMap/Sources/Data/PlanStore.swift` — 予定の端末内保存（Documents/plans.json）とCRUD、「今ここ」の保持（isPresence の予定として保存、2時間除外・移動で置き換え）、犬の名前の使い回し
- `WanMap/Sources/Data/FriendStore.swift` — 友達データの端末内保存（Documents/friends.json）。自分のID（表示ID／内部ID）、ID検索・申請（モック：自動承認）、受信申請の承認・拒否、「見せない」リスト。実通信はまだ無い
- `WanMap/Sources/Data/StoryTextParser.swift` — ストーリー／投稿テキストの貼り付け取り込み用パーサー（UIから分離した純粋ロジック）。場所（施設名・自分の場所名の正規化照合）・日付表現・時間帯の語から下書き（StoryTextDraft）を作る。確度（上限「中」）と根拠メモは下書きだけの情報で、Planには持ち込まない
- `WanMap/Sources/Data/SeedData.swift` — 仮想ユーザーの予定データ（DEBUG専用、プレビュー／検証用）
- `WanMap/Sources/Location/LocationService.swift` — 現在地の取得（SwiftLocation経由：フォアグラウンドは精度10m級の継続取得、バックグラウンド／終了後の再開は有意な位置変化ベース。非表示モード・GPS揺らぎ抑制（25m／2分）・段階的な許可リクエスト（WhenInUse→Always格上げは設定画面から）・許可状態の公開を実装。新規の位置は `onLocationFix` 経由で PlanStore の「今ここ」置き換えに流れる）
- `WanMap/Sources/Location/MockLocationManager.swift` — DEBUG専用の位置モック（`LocationManagerProtocol` 実装）。仮想の座標を流し込んで「移動→今ここが置き換わる」を実機なしで確認するための差し替え口と確認用プレビュー
- `WanMap/Sources/Views/` — RootView（カレンダー／地図／イベントのタブ。起動時・フォアグラウンド復帰時に共有シートの保留を確認し、あれば取り込み画面を開く）、CalendarView、DogMapView（＋施設シート、日付ストリップ＋時間帯での予定絞り込み、友達レール、施設検索、予定アイコンの浮遊＋指から逃げる動き、地点登録＝中心ピンで場所を追加）、UserPlaceFormView（場所の追加・編集フォームと、自分の場所の情報シート。予定フォームの候補にも自分の場所が優先で出る）、StoryImportView（テキスト貼り付け取り込み：文面＋投稿日から下書き候補を作り、タップで予定フォームを開く。自動保存はせず、保存はフォーム経由のみ。カレンダー画面のアイコンボタン、または共有シート経由（初期テキスト付き）で開く）、InfoBannerView（広告／イベント告知バナー。地図・カレンダーの上部に共通の枠）、FriendsView（友達モック：ID表示・検索・申請・QR生成とコード追加）、SettingsView（自分のID、見せない相手＝友達画面と連動、位置情報の説明、データリセット）。友達画面と設定画面はカレンダー／地図の両方からアイコンボタンで開ける
- `WanMap/Shared/SharedImportInbox.swift` — 共有シート拡張と本体の受け渡し場所（App Groups `group.jp.wanmap.app` の共有UserDefaults）。拡張側はテキストと受信日時を「保留中の取り込み」として置くだけで、解析・保存は本体側が行う
- `WanMap/ShareExtension/` — 共有シート拡張（WanMapShareターゲット）。iOSの共有シートからテキスト（およびURL付きテキスト）だけを受け、冒頭プレビュー＋「取り込む／キャンセル」の最小UIを出す。取り込むと共有置き場に保留を置いて閉じ、本体が次に開いた時に取り込み画面で下書き化する
  - **正直な線引き**：これは iOS の共有シート経由の取り込みであり、**Instagram アプリ内の拡張ではない**。Instagram と自動でつながって投稿を取得する仕組みでもない。対象になるのは、本人が共有操作をした文面だけ
- `WanMap/project.yml` — XcodeGen 用の定義。施設JSONは `WanMap/Resources/facilities.json` に置く
  （最新の書き出しは `../facility-data/facilities.json`、620件）
- `WanMap/Tests/` — 単体テスト（WanMapTestsターゲット、アプリ本体をホストに実行）。UIに依存しない純粋ロジックを守る：StoryTextParser の日付・時間帯・場所照合と確度、FacilityStore の正規化と検索（過去バグ「bで BamBoo's が出ない」の回帰防止）、Plan／PlanStore の「今ここ」2時間失効と移動での置き換え、UserPlaceStore のCRUD・検索
- `.github/workflows/build.yml` — GitHub Actions（macOS）で署名なしビルド検証＋シミュレータでの単体テスト実行をするCI（シミュレータは機種名固定でなく利用可能な iPhone から動的に選択）
- `DATA_UPDATE_DESIGN.md` — 施設データをアプリ再審査なしで更新する仕組みの設計
- 利用ライブラリ：ClusterMap 3.0.0（https://github.com/vospennikov/ClusterMap、MIT License、SPMで導入）— 地図の施設マーカーのクラスタリング計算（`DogMapView` の施設表示を差分描画にしている。予定アイコンは対象外）
- 利用ライブラリ：SwiftLocation 6.0（https://github.com/malcommac/SwiftLocation、MIT License、Copyright (c) Daniele Margutti、SPMで導入）— CoreLocation の async/await ラッパー（`LocationService` の継続取得・有意な位置変化・許可リクエスト。フェーズIで導入）

## ビルド方法

1. 本人のMac：XcodeGen を入れて `WanMap/` で `xcodegen generate` → Xcodeで開く
2. クラウド：このフォルダをGitHubリポジトリにpushすれば、Actionsが自動でビルド検証する

## 未実装（これから詰める）

- アカウント基盤（Sign in with Apple／Instagram連携ログイン）とサーバー同期
- 友達機能の実通信（モックUIは実装済み。申請・承認・通知の実通信）とQR実カメラ読み取り（現状はコード手入力で追加）
- バックグラウンド位置の実機挙動確認と審査対応（土台はフェーズIで実装済み：SwiftLocation組み込み、有意な位置変化による再開、`UIBackgroundModes: location`、段階的な許可リクエスト（WhenInUse→Always）、設定画面への許可状態の正直な表示、DEBUGモックでの差し替え口。**コンパイル確認済み／実機での再開・反映の挙動は未確認**で、TestFlight段階で確認する。App Store審査向けの説明文整備も残り）
- 施設連携（施設オーナーのInstagram投稿→下書き→確認公開）
- 共有シート取り込みの実機挙動確認（土台はフェーズJで実装済み：Share Extension＋App Groups受け渡し。**コンパイル確認待ち／実機での共有シート表示・受け渡しは未確認**で、TestFlight段階で確認する。あくまで共有シート経由であり、Instagramアプリ内の拡張・投稿の自動取得ではない）
- イベント募集への参加・承認機能（イベント一覧の表示自体は実装済み）
- 予定データのサーバー同期（現状は端末内保存のみ）
