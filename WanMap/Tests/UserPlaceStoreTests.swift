import XCTest
@testable import WanMap

/// UserPlaceStore の CRUD と検索の基本動作の検証。
/// 保存しないサンプル経路（init(samplePlaces:)）だけを使う。
final class UserPlaceStoreTests: XCTestCase {

    func testCRUD_追加すると検索でヒットし削除すると消える() {
        let store = UserPlaceStore(samplePlaces: [])
        let place = makeUserPlace(name: "うちのドッグラン")

        store.add(place)
        XCTAssertEqual(store.places.count, 1)
        XCTAssertTrue(store.search("ドッグラン").contains { $0.id == place.id })
        XCTAssertTrue(store.search("うち").contains { $0.id == place.id })

        store.remove(place)
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertTrue(store.search("ドッグラン").isEmpty)
    }

    func testUpdate_名前を変えると新しい名前で検索できる() {
        let store = UserPlaceStore(samplePlaces: [])
        var place = makeUserPlace(name: "旧ラン")
        store.add(place)

        place.name = "新ラン"
        store.update(place)

        XCTAssertTrue(store.search("新ラン").contains { $0.id == place.id })
        XCTAssertTrue(store.search("旧ラン").isEmpty)
    }

    func testSearch_英字の表記ゆれを吸収する() {
        let store = UserPlaceStore(samplePlaces: [makeUserPlace(name: "Oreo Park")])
        XCTAssertEqual(store.search("oreo").count, 1)
        XCTAssertEqual(store.search("ＯＲＥＯ").count, 1, "全角英字でもヒットするはず")
        XCTAssertTrue(store.search("").isEmpty)
    }

    func testVisibility_デフォルトは招待した人だけ() {
        // 公開範囲を指定せずに作った場所は、一番狭い「招待した人だけ」になる（決定済み仕様）
        let place = makeUserPlace(name: "庭のラン")
        XCTAssertEqual(place.visibility, .inviteOnly)
    }
}
