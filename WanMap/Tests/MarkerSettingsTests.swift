import XCTest
@testable import WanMap

/// チップの種類・犬種の並び替えの設定（MarkerSettings）の検証。
/// テスト専用の UserDefaults スイートを使い、実設定には触らない。
final class MarkerSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MarkerSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefault_チップは頭文字で並びは人気順() {
        let settings = MarkerSettings(defaults: defaults)
        XCTAssertEqual(settings.chipStyle, .initial, "既定は現状の頭文字チップ")
        XCTAssertEqual(settings.breedSort, .popularity)
    }

    func testChipStyle_変更が保存されて読み直せる() {
        let settings = MarkerSettings(defaults: defaults)
        settings.chipStyle = .breedIcon
        let reloaded = MarkerSettings(defaults: defaults)
        XCTAssertEqual(reloaded.chipStyle, .breedIcon)
    }

    func testBreedSort_変更が保存されて読み直せる() {
        let settings = MarkerSettings(defaults: defaults)
        settings.breedSort = .kana
        let reloaded = MarkerSettings(defaults: defaults)
        XCTAssertEqual(reloaded.breedSort, .kana)
    }

    func testLaunchArgument_撮影用の強制は保存値より優先し保存されない() {
        let settings = MarkerSettings(defaults: defaults,
                                      launchArguments: ["-wmChipStyle", "breedIcon"])
        XCTAssertEqual(settings.chipStyle, .breedIcon)
        let reloaded = MarkerSettings(defaults: defaults)
        XCTAssertEqual(reloaded.chipStyle, .initial, "起動引数の上書きは保存されないこと")
    }
}

/// 自分の犬の更新（FriendStore）と、AppUser の後方互換（旧JSONに犬種項目が無い）の検証。
final class MyDogProfileTests: XCTestCase {

    func testUpdate_犬種を変えると毛色は未設定に戻る() {
        let store = FriendStore.preview
        store.updateMyDogBreed(breedId: "shiba")
        store.updateMyDogColor(colorId: "red")
        XCTAssertEqual(store.me.dogColorId, "red")
        store.updateMyDogBreed(breedId: "toy-poodle")
        XCTAssertEqual(store.me.breedId, "toy-poodle")
        XCTAssertNil(store.me.dogColorId, "犬種が変わったら前の犬種の毛色を引き継がない")
    }

    func testUpdate_同じ犬種の選び直しでは毛色が残る() {
        let store = FriendStore.preview
        store.updateMyDogBreed(breedId: "shiba")
        store.updateMyDogColor(colorId: "sesame")
        store.updateMyDogBreed(breedId: "shiba")
        XCTAssertEqual(store.me.dogColorId, "sesame")
    }

    func testUpdate_名前の前後空白は除かれ空は未設定になる() {
        let store = FriendStore.preview
        store.updateMyDogName(" ハス太 ")
        XCTAssertEqual(store.me.dogName, "ハス太")
        store.updateMyDogName("  ")
        XCTAssertNil(store.me.dogName)
    }

    func testAppUser_旧形式JSONでも犬種なしで読み込める() throws {
        // breedId / dogColorId が無い旧バージョンの保存データを壊さない
        let legacy = """
        {"internalId":"usr-legacy","appIssuedId":"wan-legacy","displayName":"自分","dogName":"ムギ"}
        """
        let user = try JSONDecoder().decode(AppUser.self, from: Data(legacy.utf8))
        XCTAssertEqual(user.dogName, "ムギ")
        XCTAssertNil(user.breedId)
        XCTAssertNil(user.dogColorId)
    }

    func testAppUser_犬種ありが往復で保持される() throws {
        var user = FriendStore.preview.me
        user.breedId = "siberian-husky"
        user.dogColorId = "red-white"
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(AppUser.self, from: data)
        XCTAssertEqual(decoded.breedId, "siberian-husky")
        XCTAssertEqual(decoded.dogColorId, "red-white")
    }
}
