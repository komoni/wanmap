import XCTest
@testable import WanMap

/// 犬種マスタ（BreedStore）の検証：同梱マスタの読込、検索の揺れ吸収、
/// 並び替え、地図アイコンの解決（未設定・未制作はミックスに倒す本人の決定）。
final class BreedStoreTests: XCTestCase {

    private var store: BreedStore!

    override func setUp() {
        super.setUp()
        store = BreedStore()
        store.remoteURL = nil  // テスト中にネットワークへ出ない
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - 同梱マスタ

    func testBundledMaster_犬種と毛色が読み込める() {
        XCTAssertGreaterThanOrEqual(store.breeds.count, 40, "現行39種＋その他の犬種が入っていること")
        let colorCount = store.breeds.reduce(0) { $0 + $1.colors.count }
        XCTAssertEqual(colorCount, 107, "毛色の総数はラインアップ表（107）と一致すること")
    }

    func testBundledMaster_制作済みアイコンは15枚() {
        let iconCount = store.breeds.flatMap(\.colors).filter { $0.icon != nil }.count
        XCTAssertEqual(iconCount, 15, "ハスキー4＋プードル5＋チワワ5＋ミックス1")
    }

    // MARK: - 正規化と検索

    func testNormalize_カタカナはひらがなにそろう() {
        XCTAssertEqual(BreedStore.normalize("シバ"), "しば")
        XCTAssertEqual(BreedStore.normalize("しば"), "しば")
    }

    func testNormalize_長音は残る() {
        XCTAssertEqual(BreedStore.normalize("トイプードル"), "といぷーどる")
    }

    func testSearch_読みの表記違いで柴犬が見つかる() {
        for query in ["しば", "シバ", "柴", "しばいぬ", "柴犬"] {
            let results = store.search(query)
            XCTAssertTrue(results.contains { $0.id == "shiba" },
                          "「\(query)」で柴犬が見つかること： \(results.map(\.id))")
        }
    }

    func testSearch_別名でトイプードルが見つかる() {
        let results = store.search("トイプー")
        XCTAssertEqual(results.first?.id, "toy-poodle")
    }

    func testSearch_英名でも見つかる() {
        let results = store.search("husky")
        XCTAssertTrue(results.contains { $0.id == "siberian-husky" })
    }

    func testSearch_該当なしは空を返す() {
        XCTAssertTrue(store.search("ぞうさん").isEmpty)
    }

    // MARK: - 並び替え

    func testSort_人気順は安定している() {
        let sorted = store.sorted(store.breeds, by: .popularity)
        XCTAssertEqual(sorted.map(\.popularity), sorted.map(\.popularity).sorted())
    }

    func testSort_サイズ順は小型が先に来る() {
        let sorted = store.sorted(store.breeds, by: .size)
        let orders = sorted.map(\.size.sortOrder)
        XCTAssertEqual(orders, orders.sorted())
    }

    func testSort_50音順は読みで並ぶ() {
        let sorted = store.sorted(store.breeds, by: .kana)
        XCTAssertEqual(sorted.map(\.kana), sorted.map(\.kana).sorted())
    }

    func testSort_下からは昇順の反転になる() {
        for sort in BreedSort.allCases {
            let ascending = store.sorted(store.breeds, by: sort, ascending: true)
            let descending = store.sorted(store.breeds, by: sort, ascending: false)
            XCTAssertEqual(descending.map(\.id), ascending.map(\.id).reversed(),
                           "\(sort) の降順は昇順の反転であること")
        }
    }

    // MARK: - アイコン解決（本人の決定：未設定・未制作はミックス）

    func testMarkerIcon_制作済みの犬種と色はそのアイコン() {
        XCTAssertEqual(store.markerIconAsset(breedId: "siberian-husky", colorId: "black-white"),
                       "breed_siberian-husky_black-white")
    }

    func testMarkerIcon_未制作の色はミックスに倒れる() {
        XCTAssertEqual(store.markerIconAsset(breedId: "shiba", colorId: "red"),
                       BreedStore.fallbackIconAsset)
    }

    func testMarkerIcon_犬種未設定はミックス() {
        XCTAssertEqual(store.markerIconAsset(breedId: nil, colorId: nil),
                       BreedStore.fallbackIconAsset)
    }

    func testMarkerIcon_存在しない犬種IDでも壊れずミックス() {
        XCTAssertEqual(store.markerIconAsset(breedId: "no-such-breed", colorId: "red"),
                       BreedStore.fallbackIconAsset)
    }
}
