import XCTest
@testable import WanMap

/// FacilityStore.normalize と検索の検証。
/// 過去の実バグ「検索欄に b と打っても BamBoo's が出ない」の回帰防止が主目的。
final class FacilityStoreTests: XCTestCase {

    // MARK: - 正規化ルール

    func testNormalize_全角英字は半角の小文字になる() {
        XCTAssertEqual(FacilityStore.normalize("ＢＡＭＢＯＯ"), "bamboo")
    }

    func testNormalize_大文字は小文字になる() {
        XCTAssertEqual(FacilityStore.normalize("BamBoo"), "bamboo")
    }

    func testNormalize_アポストロフィは取り除かれる() {
        XCTAssertEqual(FacilityStore.normalize("BamBoo's"), "bamboos")
        XCTAssertEqual(FacilityStore.normalize("BAMBOO'S"), "bamboos")
    }

    func testNormalize_空白は取り除かれる() {
        XCTAssertEqual(FacilityStore.normalize("ドッグ ウィズ"), FacilityStore.normalize("ドッグウィズ"))
    }

    func testNormalize_表記違いが同じキーになる() {
        XCTAssertEqual(FacilityStore.normalize("ＢａｍＢｏｏ＇ｓ"),
                       FacilityStore.normalize("bamboos"))
    }

    // MARK: - 検索（フィクスチャに対する回帰テスト）

    /// 過去の実バグ「検索欄に b と打っても BamBoo's が出ない」の再現条件を、固定フィクスチャで守る
    private func fixtureStore() -> FacilityStore {
        FacilityStore(facilities: [
            makeFacility(name: "BamBoo's", displayName: "BamBoo's（バンブーズ）"),
            makeFacility(name: "BAMBOO DOGS"),
            makeFacility(name: "ドッグウィズ"),
        ])
    }

    func testSearch_bの一文字でBamBoosが引ける() {
        let results = fixtureStore().search("b")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" },
                      "「b」の検索で BamBoo's が出ませんでした（過去バグの再現）")
    }

    func testSearch_全角の大文字でもBamBoosが引ける() {
        let results = fixtureStore().search("ＢＡＭＢＯＯ")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" })
    }

    func testSearch_アポストロフィ無しでもBamBoosが引ける() {
        let results = fixtureStore().search("bamboos")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" })
    }

    func testSearch_空文字と空白だけの検索は空を返す() {
        let store = fixtureStore()
        XCTAssertTrue(store.search("").isEmpty)
        XCTAssertTrue(store.search("　").isEmpty)
    }

    // MARK: - 同梱データの統合テスト

    /// アプリ同梱の facilities.json が実際に読み込めていることの確認。
    /// ここが落ちる場合は「検索」ではなく「同梱データの読み込み」自体の問題（実機でも施設が0件になる重大不具合）。
    func testBundledJSON_同梱データが読み込めてBamBoosが検索できる() {
        let store = FacilityStore()
        XCTAssertEqual(store.facilities.count, 620,
                       "同梱JSONが読み込めていません（読み込み件数: \(store.facilities.count)）")
        XCTAssertTrue(store.search("b").contains { $0.name == "BamBoo's" })
    }
}
