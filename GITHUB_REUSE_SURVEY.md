# GitHub再利用コード追加調査（2026-11-05確認）

既存の `OSS_REFERENCES.md`（2026-11-03）の続き。新規候補と、既出候補の深掘り（SPM対応・導入手順の具体化）をまとめる。ライセンスは各リポジトリのGitHubページ／LICENSE本文を目視確認したものだけを記載する。

凡例：=今回追加、=OSS_REFERENCES.md掲載済みで情報を具体化、=ライセンス上コード流用不可またはサービス前提で導入しないもの。

## 共通：XcodeGen（project.yml）へのSPM追加手順

現在の `WanMap/project.yml` は依存パッケージなし（packages未定義）。SPM対応ライブラリはすべて次の形で追加できる（例はClusterMap）：

```yaml
packages:
ClusterMap:
url: https://github.com/vospennikov/ClusterMap
from: 3.0.0
targets:
WanMap:
dependencies:
- package: ClusterMap
```

注意：パッケージを追加するとGitHub ActionsのCIでSPM解決が走り、初回ビルド時間が延びる。バージョンはタグ固定（branch指定は避ける）。

---

## 1. 地図クラスタリング／大量マーカー

### ClusterMap（第一候補のまま）
- URL: https://github.com/vospennikov/ClusterMap
- ライセンス: MIT（変更なし）
- SPM: **対応確定**。Swift Package Index掲載、現行 **3.0.0**（2026-09リリース）、`.package(url: "https://github.com/vospennikov/ClusterMap.git", from: "3.0.0")`、**依存パッケージなし**
- 構成: 本体 `ClusterMap`（QuadTree＋actor の ClusterManager、UI非依存）＋ `ClusterMapSwiftUI`（SwiftUI連携、`.readSize` 等）。リポジトリ内に Example-SwiftUI があり、iOS 17 の SwiftUI Map との繋ぎ込み例になっている
- 対応機能・ファイル: 施設約620件＋人のアイコンの表示更新 → `Sources/Views/DogMapView.swift`。施設と人のアイコンを `CoordinateIdentifiable` 化し、表示範囲とズームからクラスタ計算→差分だけAnnotationを入れ替える
- 導入の手間: 中。project.ymlへの追加自体は上記の数行だが、SwiftUI Map の Annotation 差し替え設計と噛み合わせる作業が本体
- 注意点: 620件規模＋現行のズーム切替表示でも実用上は動くため、導入条件は「描画が重い・チラつくようになったら」。最初から入れる必要はない

### Cluster（efremidze）— MKMapViewへ移行する場合の本命
- URL: https://github.com/efremidze/Cluster
- ライセンス: **MIT**（GitHubページで目視確認）、⭐約1,292
- SPM: 対応（Package.swift あり、SPMバッジあり。READMEの導入案内はCocoaPods/Carthage中心の古い書き方）
- 内容: QuadTreeで MKMapView のアノテーションをクラスタリングする老舗。ClusterMap の原典（作者が同じ系統）。`ClusterManager` が add/remove/reload と差分管理を持ち、`maxZoomLevel` で「拡大したらクラスタ解除」も標準機能
- 対応機能・ファイル: `DogMapView.swift` を SwiftUI Map から MKMapView（UIViewRepresentable）へ置き換える場合にのみ意味がある
- 導入の手間: 大（地図実装そのものの置き換えになる）
- 注意点: SwiftUI Map を使い続けるなら ClusterMap の方が適合。こちらは「SwiftUI Map の表現力に限界を感じて MKMapView 化する」場合の選択肢として保持

### Meshtastic-Apple の地図刷新PR（GPL-3.0）
- https://github.com/meshtastic/Meshtastic-Apple/pull/1989 （本体は既出のGPLリポジトリ）
- MKMapView＋ネイティブ `clusteringIdentifier`＋ID差分適用（チラつきなし）を SwiftUI から宣言的に使う実装が2026年に追加された。「SwiftUI Map をやめて MKMapView ラッパにする」判断をする時の完成形の見本。閲覧のみ

## 2. カレンダー（月表示・年表示）

### HorizonCalendar（Airbnb）— 月表示を作り込むなら最有力
- URL: https://github.com/airbnb/HorizonCalendar
- ライセンス: **Apache-2.0**（GitHubページで目視確認）、⭐約3,164
- SPM: 対応（Package.swift あり、現行2.0.0系。依存パッケージが2件ある点はSPI表示で確認）
- 内容: Airbnb本番アプリで使われている宣言的カレンダー。SwiftUIからは `CalendarViewRepresentable` で利用可。日セル・月ヘッダ・曜日・月の背景装飾まで SwiftUI View で差し替え可能で、パステル配色＋🐶マークのような全面カスタムが前提の設計。Foundation.Calendar 準拠なので週の開始曜日や和暦も扱える。縦/横スクロール、任意日へのスクロール、無限に近い日付範囲に対応
- 対応機能・ファイル: `Sources/Views/CalendarView.swift` の月表示の基盤。年表示（12ヶ月俯瞰グリッド）は守備範囲外なので自前 yearGrid を継続
- 導入の手間: 中（content の組み立て方に学習コスト。既存の自前月表示からの置き換え）
- 注意点: 月表示のスクロール挙動・カスタム度で困った時の乗り換え先。現行の自前実装＋Mijick想定で足りている間は急がない

### ElegantCalendar — 純SwiftUIで年表示まで揃う候補
- URL: https://github.com/ThasianX/ElegantCalendar
- ライセンス: **MIT**（GitHubページで目視確認）、⭐約1,094
- SPM: 対応（`from: "4.2.0"`）
- 内容: 純SwiftUI。`MonthlyCalendarView` と `YearlyCalendarView` の両方が入り、月⇔年の遷移と「今日へ戻る」ボタンまで標準装備。テーマ（色）＋ datasource で日ごとの装飾・選択可否・選択時のアクセサリ表示を差し替え可能
- 対応機能・ファイル: `CalendarView.swift`、特に**年表示**を自前で作り込む前の検証枠として
- 導入の手間: 中
- 注意点: (1) 同作者の ElegantPages に依存。(2) README自身が明記する通り、年表示は全年度ビューを先読みする設計で、対象期間を広げると初期描画が重くなる。(3) ObservableObject 世代のコードで、WanMap の `@Observable` との統合に薄いラッパが要る。採用前に年表示の描画速度を必ず実測すること

### Mijick/CalendarView
- ライセンス: MIT（GitHubページで再確認）、⭐約578
- SPM: 対応（Package.swift あり、iOS 14+）。ただし README の導入例が `branch("main")` 指定で、リリースは3件のみ。導入時は**リリースタグで版固定できるか先に確認**すること（固定できない場合は依存更新で突然壊れるリスク）
- 具体化: カスタマイズは `configBuilder` で `.dayView(...)` / `.weekdaysView(...)` / `.monthLabel` 等を差し替える方式。日セル全面カスタムは可能。年表示はなし（既出の評価どおり）
- 導入の手間: 小〜中。対応ファイルは `CalendarView.swift`（月表示のみ）

### KVKCalendar
- ライセンス: MIT（変更なし）
- SPM: **対応を Swift Package Index で確認**（iOS 13+、UIKit＋EventKit、day/week/month/year/list の5モジュール）
- ただし最終リリース 0.6.30 は2023-10で、メンテナンスは停滞気味。既定どおり「年表示レイアウトの設計参考」に留め、組み込みはしないのが安全

## 3. リモートJSON取得／キャッシュ

### configcat/swift-sdk
- URL: https://github.com/configcat/swift-sdk
- ライセンス: **MIT と確定**。GitHubの自動判定は「Other (NOASSERTION)」表示だが、LICENSE本文を目視したところ MIT License 本文だった（同梱コンポーネント mxcl/Version は Apache-2.0 と明記）。前回調査の「ライセンス要確認」はこれで解消
- SPM: 対応（`from: "11.3.1"`）
- 位置づけは不変: ホスト型のフラグ配信サービス前提であり、施設JSONは自前配信（DATA_UPDATE_DESIGN.md）が決定済み。CDN取得＋ポーリング＋キャッシュ差し替えの**設計参考**として残す。導入はしない想定

### GrowthBook Swift SDK — 取得・キャッシュ・更新通知の実装参考
- URL: https://github.com/growthbook/growthbook-swift
- ライセンス: **MIT**（GitHubページで目視確認。SDK単体リポジトリのライセンス）、⭐約26（本体プラットフォーム側は別リポジトリで大規模）
- SPM: 対応（`from: "2.0.0"`、製品名 `GrowthBook-IOS`）。リリース頻度が高い（126件）
- 内容: リモートJSON取得→ローカルキャッシュ→ `refreshHandler` での更新通知、ストリーミング更新、オフラインモード、という FacilityStore の「完成形」に近い作り
- 対応機能・ファイル: `Sources/Data/FacilityStore.swift` の設計参考（取得・キャッシュ・版数/更新通知の分離の仕方）
- 導入の手間: 中（＋ GrowthBook のサーバー/SaaS の用意が前提になる）
- 注意点: 施設JSON配信そのものには導入しない（自前JSONで足りる）。将来「機能フラグ」「お知らせバナーの出し分け」「A/Bテスト」が要る段階で初めて導入候補になる

### Cache（hyperoslo）— Codable特化のキャッシュ層
- URL: https://github.com/hyperoslo/Cache
- ライセンス: **MIT**（LICENSE.md 本文を目視確認。GitHub自動判定は NOASSERTION 表示なので本文確認が必須だった）、⭐約3,140
- SPM: 対応（Package.swift あり）
- 内容: Codable なオブジェクトをメモリ＋ディスクの Hybrid Storage に保存する専用ライブラリ。有効期限（expiry）の管理と期限切れ掃除が内蔵、async/await 対応
- 対応機能・ファイル: `FacilityStore` のキャッシュ層。転用先として、予定の下書きや「2時間で消える」類の期限付き保存にも使える形をしている
- 導入の手間: 小
- 注意点: メンテナンスは緩やか。現状の FacilityStore は約70行の自前実装で足りており、置き換えの必然性はない。「キャッシュ対象（予定・友達・下書き）が増えて自前管理が煩雑になったら」が導入条件

### firebase/quickstart-ios（config/）
- 評価は変更なし。Remote Config の fetch→キャッシュ→activate→失敗時は前回値、という作法は現在の FacilityStore の3段構えと一致している。Firebase 自体を導入する場合のみ実物を使う

## 4. バックグラウンド位置情報

### SwiftLocation（第一候補のまま、情報更新）
- ライセンス: MIT（GitHubページで再確認）、⭐約3,419
- SPM: 現行 **6.x は SPM 専用配布**（`from: "6.0.0"`、iOS 14+、Swift 5.5+）
- 具体化: `startMonitoringSignificantLocationChanges()` と `startMonitoringVisits()` が AsyncStream で使える。WanMap の「大きな移動だけ拾う」方針と一致。テスト用に **MockedLocationManager が同梱**されており、仮想データで操作検証する方針（本番に仮想データを入れない）と相性が良い
- 対応機能・ファイル: `Sources/Location/LocationService.swift` の delegate 実装を async 化する置き換え候補
- 導入の手間: 中。2時間自動消去タイマ・非表示モード・「勝手に地図中心を動かさない」等の仕様ロジックは自前側に残し、取得イベントの受け口だけ差し替える形にする

### AsyncLocationKit（AsyncSwift）— SwiftLocation の対抗
- URL: https://github.com/AsyncSwift/AsyncLocationKit
- ライセンス: **MIT**（GitHubページで目視確認）、⭐約200
- SPM: 対応（`from: "2.0.1"`）、**依存パッケージゼロ**
- 内容: CoreLocation の async/await ラッパー。continuous updates / significant changes / visits / region monitoring（ジオフェンス相当）/ バックグラウンド更新の許可フラグまで一通り AsyncStream 化されている。Swift 6 の Sendable 準拠を明記
- 対応機能・ファイル: `LocationService.swift`（SwiftLocation と同じ置き換え先）
- 導入の手間: 中
- 注意点: 機能の網羅は同等だが、利用実績・枯れ具合は SwiftLocation が大きく上。どちらか一方で十分で、原則 SwiftLocation 優先、こちらは「依存ゼロ・Swift 6 準拠を重視する場合」の代替

### 補足（既出の再確認）
- ジオフェンスの本命は Apple 公式サンプルの **CLMonitor**（iOS 17〜）。上記ラッパ2件はいずれも CLCircularRegion 時代の region monitoring が中心なので、「施設に近づいたら」の監視を CLMonitor で組む部分は標準API直書きが前提になる

## 5. OAuth（Instagram連携）

### AppAuth-iOS（本命のまま、手順を具体化）
- ライセンス: Apache-2.0（GitHubページで再確認）、⭐約2,038
- SPM: 対応。現行 **3.0.0 系**（`.upToNextMajor(from: "3.0.0")`）。**CocoaPods 配布は終了宣言済み**なので SPM 一択。製品は `AppAuth` / `AppAuthCore`（拡張ターゲット用）/ `AppAuthTV`
- 実装例の在りか: リポジトリ内 `Examples/` に Swift サンプル一式。特に「認可コードの交換を自前で行う」例（authNoCodeExchange）が、**トークン交換はサーバー側**という WanMap の前提にそのまま対応する（アプリはコード取得まで、交換は自前サーバーへ）
- Instagram向けの具体注意:
- Instagram は OIDC discovery 非対応なので、`OIDServiceConfiguration` に認可エンドポイントとトークンエンドポイントを直接指定する
- リダイレクトはカスタムURIスキームが現実解。HTTPSリダイレクトは iOS 17.4+ ＋ webcredentials の Associated Domains 設定が必要で手間が大きい
- PKCE は標準で有効。`OIDAuthState` の保持がセッション管理の単位になる
- 対応機能・ファイル: 新規 `Sources/Auth/`（例: InstagramAuthService）＋ `WanMapApp.swift` 側のURLハンドリング追加
- 導入の手間: 中（ライブラリ側は薄い。Meta審査とサーバー側トークン交換の用意が本体の工数）

### OAuthSwift — AppAuth が詰まった場合の代替
- URL: https://github.com/OAuthSwift/OAuthSwift
- ライセンス: **MIT**（GitHubページで目視確認）、⭐約3,326
- SPM: 対応（`from: "2.2.0"`）。OAuth 1.0/2.0 両対応、PKCE 対応、README に Instagram 認可の実装例そのものがある
- 対応機能・ファイル: AppAuth と同じ置き換え先（`Sources/Auth/`）
- 導入の手間: 中
- 注意点: README の Instagram 例は旧式の implicit 前提の書き方で、そのままは使えない。認可画面の出し方も SFSafariViewController 世代の設計で、ASWebAuthenticationSession 前提の AppAuth の方が現在の標準に合う。メンテナンス速度も緩やか（最終更新は2024年頃）。あくまで代替候補

## 6. Share Extension（共有シートからの取り込み）

### 結論：導入すべき「ライブラリ」は存在しない領域
- 共有拡張は Xcode テンプレート（`SLComposeServiceViewController`）が土台で、SPMライブラリを入れる性質のものではない。今回の調査範囲でも、ライセンスが確認できて導入に値する専用ライブラリ/サンプルは見つからなかった
- 必要な作業は3点に集約される:
1. 本体と拡張の両方に **App Groups** の entitlements（project.yml に app-extension ターゲットと entitlements を追加）
2. 拡張側 Info.plist の `NSExtensionActivationRule` で受け付ける種別（テキスト/URL/画像）を宣言
3. 拡張が共有コンテナ（App Group の UserDefaults / ファイル）に書き込み、本体アプリが起動・復帰時に回収して下書き化する（WanMap では貼り付けテキスト解析の下書きフローに合流させる）
- 導入の手間: 中（ライブラリ選定ではなくターゲット追加と受け渡し実装の作業）

### 実装手順の読み物（候補ではない）
- OSSプロジェクト内の設計ドキュメント2件が、上記「App Group に書いてから本体が回収する」実務パターンを具体化している:
- pocketnetteam/forta.chat の iOS Share Extension 計画ドキュメント（`docs/plans/ios/2026-05-12-ios-share-extension.md`）
- fdittgen-png/tankstellen の iOS Share Extension 導入ガイド（`docs/guides/ios-share-extension.md`）
- ※両プロジェクト自体のライセンスは今回未確認のため、**候補には入れない**。手順の読み物として参照するに留め、コードの転載はしないこと

### 参考調査の結果（正直な記録）
- 実プロダクトの参考として Wikipedia 公式アプリ（https://github.com/wikimedia/wikipedia-ios 、**MIT** を目視確認、⭐約3,473）の拡張分割構成を見たが、現行リポジトリのルートに Share Extension ターゲットは見当たらなかった（Widget/通知拡張のみ）。共有拡張の参考としては外す

---

## 設計参考のみ（GPL）まとめ
- Meshtastic-Apple（GPL-3.0、既出）＋ その地図刷新PR #1989（上記1章）
- 今回、新規のGPL候補は追加していない

## 候補から除外したもの
- Mcrich23/SwiftUIMap: SwiftUI Map の UIKit ラッパとして検索に上がったが、README のライセンス表記に別ライブラリの文面混入が見られ、表記を信用しきれないため候補外とした

## 推奨導入順
1. **ClusterMap**（既出・深掘り済み）— 地図の差分適用が必要になった段階で。SPM・版固定・依存なしまで確認済みで、一番「入れるだけ」に近い
2. **SwiftLocation 6.x** — バックグラウンド位置を実装する段階で LocationService を async 化。モック同梱が検証方針に合う
3. **AppAuth-iOS 3.x** — Instagram連携の実装段階で。サーバー側トークン交換のサンプル例が前提と一致する
4. **HorizonCalendar** — 月表示を作り込む段階で、Mijick と実機比較して一方に決める（年表示は自前継続）
5. **ElegantCalendar** — 年表示の検証枠としてのみ試す（描画速度の実測が条件）
6. 条件付き: **Cache**（キャッシュ対象が増えたら）、**GrowthBook SDK**（フラグ/出し分けが必要になったら）
7. **Share Extension** — ライブラリ選定ではなく「ターゲット追加タスク」として実装計画に組み込む
