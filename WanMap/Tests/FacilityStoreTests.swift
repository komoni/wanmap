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

    // MARK: - 検索（同梱施設データに対する回帰テスト）

    func testSearch_bの一文字でBamBoosが引ける() {
        // テストホスト（アプリ本体）の同梱JSONに BamBoo's が含まれる前提の回帰テスト
        let store = FacilityStore()
        let results = store.search("b")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" },
                      "「b」の検索で BamBoo's が出ませんでした（過去バグの再発）")
    }

    func testSearch_全角の大文字でもBamBoosが引ける() {
        let store = FacilityStore()
        let results = store.search("ＢＡＭＢＯＯ")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" })
    }

    func testSearch_アポストロフィ無しでもBamBoosが引ける() {
        let store = FacilityStore()
        let results = store.search("bamboos")
        XCTAssertTrue(results.contains { $0.name == "BamBoo's" })
    }

    func testSearch_空文字と空白だけの検索は空を返す() {
        let store = FacilityStore()
        XCTAssertTrue(store.search("").isEmpty)
        XCTAssertTrue(store.search("　").isEmpty)
    }
}
