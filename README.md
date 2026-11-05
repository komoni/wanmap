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
- `WanMap/Resources/Assets.xcassets` — アプリアイコン（AppIcon、フェーズL）。販促用アイコン（看板犬オレオ）を仮素材として配置してあるが、**現素材は640×640で提出用の1024×1024に足りない**。正式アイコンの差し替えは TestFlight 手順側の残作業（下記）
- `WanMap/Tests/` — 単体テスト（WanMapTestsターゲット、アプリ本体をホストに実行）。UIに依存しない純粋ロジックを守る：StoryTextParser の日付・時間帯・場所照合と確度、FacilityStore の正規化と検索（過去バグ「bで BamBoo's が出ない」の回帰防止）、Plan／PlanStore の「今ここ」2時間失効と移動での置き換え、UserPlaceStore のCRUD・検索
- `WanMap/UITests/` — 画面撮影用UIテスト（WanMapUITestsターゲット）。実機（TestFlight）前にシミュレータの実画面を目で確認するためのもの。起動引数 `-UITestingSeedData`（RootView の DEBUG 専用分岐）でシード予定が見える状態で起動し、主要5画面（カレンダー月表示／地図／イベント／日別予定／設定）を巡回してスクリーンショットを XCTAttachment（keepAlways）に残す。地図マーカーのタップ（施設シート）は座標依存で不安定なため撮影対象外。CI では単体テストと別ステップ（continue-on-error）で実行し、画像はアーティファクト `wanmap-screenshots` として保存される
- `.github/workflows/build.yml` — GitHub Actions（macOS）で署名なしビルド検証＋シミュレータでの単体テスト実行＋UIテストでの画面撮影をするCI（シミュレータは機種名固定でなく利用可能な iPhone から動的に選択）
- `DATA_UPDATE_DESIGN.md` — 施設データをアプリ再審査なしで更新する仕組みの設計
- 利用ライブラリ：ClusterMap 3.0.0（https://github.com/vospennikov/ClusterMap、MIT License、SPMで導入）— 地図の施設マーカーのクラスタリング計算（`DogMapView` の施設表示を差分描画にしている。予定アイコンは対象外）
- 利用ライブラリ：SwiftLocation 6.0（https://github.com/malcommac/SwiftLocation、MIT License、Copyright (c) Daniele Margutti、SPMで導入）— CoreLocation の async/await ラッパー（`LocationService` の継続取得・有意な位置変化・許可リクエスト。フェーズIで導入）

## フェーズN：「可愛い全面」デザインパターンの配色適用

デザイン案4案（現行／ティール統一／高級感／可愛い全面）を比較し、本人が「可愛い全面」を選択（2026-11-05）。まず配色だけを実アプリへ適用した。色値は `../codex-design-2026-11-05/patterns-notes.md` のパターン2のHEXを正とする。

- 追加：`WanMap/Sources/Views/WanStyle.swift` — 共通カラートークン（canvas ミルク #FFF8EF／card クリームホワイト #FFFEFC／coral コーラル #EE7869／apricot アプリコット #FFC879／lavender パウダーラベンダー #DCD5F2／cocoa ココア #533E38／saturday ソフトブルー #709DC6）。画面側の色はここを経由する
- 適用範囲：今日の円・選択日・選択ピル・主要ボタン（地図の「今ここ」等）はコーラル、地図クラスターはココア地＋白文字＋白フチ、カレンダーの予定行はラベンダー地のカプセル＋ココア文字のチップ表現、予定マーカーはココア／自分の「今ここ」はコーラル、友達レールは presence＝コーラル／通常＝ラベンダー（文字はココア）、日曜はコーラル・土曜はソフトブルー、バナーはアプリコット基調のグラデーション、カレンダーと地図の最背面はミルク、セル・カード面はクリームホワイト。アプリ全体と TabView の tint はコーラル（シートで開く設定・フォーム類のアクセントもこれで揃う）
- 変更していないもの：レイアウト・挙動・データ・文言は一切変更なし（予定チップの背景形状追加を除く）
- **未適用（装飾フェーズは未実施）**：犬のイラスト、ギンガムチェック、肉球の散りばめ等の装飾要素は今回入れていない。モックアップ（cute-calendar.png／cute-map.png）の装飾を再現する場合は別フェーズで検討する
- **実機での見え方は未確認**：コンパイルと画面の目視確認は CI のビルド／スクリーンショットで行い、実機確認は TestFlight 段階（従来どおり）。ダークモードは別設計が必要なため今回の対象外

## ビルド方法

1. 本人のMac：XcodeGen を入れて `WanMap/` で `xcodegen generate` → Xcodeで開く
2. クラウド：このフォルダをGitHubリポジトリにpushすれば、Actionsが自動でビルド検証する

## TestFlight までの手順（残りは本人の手続きだけ）

コード側で先に済ませてあること（フェーズLまで）：

- バンドルIDの統一：本体 `jp.wanmap.app`／共有拡張 `jp.wanmap.app.share`。App Groups `group.jp.wanmap.app` とも整合済み
- ホーム画面の表示名「WanMap」、サポート向きは縦（Portrait）のみを明示（CIの向き警告は解消済み）
- アプリアイコン：Assets.xcassets に AppIcon を配置し、project.yml から参照済み（仮素材。正式版は下記の残作業）
- CI（署名なしビルド＋単体テスト43件）が通る状態を維持している

本人の手続き（これだけが残っている）：

1. **Apple Developer Program に登録**する（年¥12,800。本人の Apple ID で登録・支払い）
2. **App Store Connect でアプリを新規作成**する：バンドルIDは `jp.wanmap.app` を選択し、アプリ名・主要言語・SKUを設定する
   - App ID と App Groups（`group.jp.wanmap.app`）の用意は、Xcode の自動署名管理（Automatically manage signing）が行う前提で、個別の手作業登録は不要の見込み
3. 登録が終わったら、その旨を知らせる（以降はコード側の作業に戻る）

登録後にこちらでやること（コード／配信側の残作業）：

- 正式アプリアイコン（1024×1024）の作成と差し替え ※現在の仮素材は販促アイコンの流用で **640×640** しかなく、提出要件を満たさないため必須
- Xcode の自動署名設定（Team の選択）を確認し、証明書・プロビジョニングプロファイルを自動管理に任せる形でアーカイブできる状態にする
- アーカイブ（Archive）して App Store Connect へアップロードする
- TestFlight の内部テストを用意し、本人の iPhone でインストールできる状態にする（輸出コンプライアンス等の必須回答への対応を含む）
- バージョン／ビルド番号の管理

TestFlight で確認する観点（フェーズA〜Kの実挙動チェックリスト）：

- カレンダー：月表示・年表示・「今日」ボタンの挙動、予定の追加・編集・繰り返し（毎週／毎月）、行く度合い（行く／多分行く／晴れなら行く）の保存
- 地図：施設マーカーのクラスタリングとズーム13での名前表示、施設シート（項目・Googleマップで開く・出典／確認日表示）、施設検索で候補タップ→ズーム15に寄るだけ（シートは開かない）、検索の表記ゆれ吸収（例：「b」で BamBoo's 系が出る）
- 予定アイコン：浮遊アニメーション、指に触れると逃げる動き、地図操作の邪魔にならないこと
- 日付ストリップ／時間帯ボタン：選択中の日付が勝手に戻らないこと、スライド操作感
- 友達レール：タップでその友達の地点へ飛ぶこと
- 「今ここ」：ワンタップ配置と取消、2時間での自動消去、移動したら前の場所が置き換わること、未登録地点では人アイコンのみ（場所名なし）になること
- バックグラウンド位置：「常に許可」にした後、アプリを閉じた状態での移動が有意な位置変化で反映されること（フェーズI。許可が使用中のみの間は反映されないことが設定画面の表示どおりであること）
- 非表示モード：予定フォーム内の切り替えで自分の位置が出なくなること、設定の「見せない相手」リストとの連動
- 場所追加：中心ピンで地点を決めて登録でき、地図・検索・予定フォームの候補に出ること（公開範囲のデフォルトが「招待した人だけ」であること）
- テキスト取り込み：貼り付け→下書き生成（自動保存されないこと）、共有シートに「WanMapに取り込む」が出て、取り込むとアプリ側で下書きとして開くこと（App Groups の受け渡し、フェーズJ）
- その他：上部バナー（地図・カレンダー共通）の表示と切り替わり、設定画面のデータリセット、ホーム画面の表示名「WanMap」とアイコンの見え方

## 未実装（これから詰める）

- アカウント基盤（Sign in with Apple／Instagram連携ログイン）とサーバー同期
- 友達機能の実通信（モックUIは実装済み。申請・承認・通知の実通信）とQR実カメラ読み取り（現状はコード手入力で追加）
- バックグラウンド位置の実機挙動確認と審査対応（土台はフェーズIで実装済み：SwiftLocation組み込み、有意な位置変化による再開、`UIBackgroundModes: location`、段階的な許可リクエスト（WhenInUse→Always）、設定画面への許可状態の正直な表示、DEBUGモックでの差し替え口。**コンパイル確認済み／実機での再開・反映の挙動は未確認**で、TestFlight段階で確認する。App Store審査向けの説明文整備も残り）
- 施設連携（施設オーナーのInstagram投稿→下書き→確認公開）
- 共有シート取り込みの実機挙動確認（土台はフェーズJで実装済み：Share Extension＋App Groups受け渡し。**コンパイル確認済み／実機での共有シート表示・受け渡しは未確認**で、TestFlight段階で確認する。あくまで共有シート経由であり、Instagramアプリ内の拡張・投稿の自動取得ではない）
- イベント募集への参加・承認機能（イベント一覧の表示自体は実装済み）
- 予定データのサーバー同期（現状は端末内保存のみ）
