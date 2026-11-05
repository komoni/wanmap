import XCTest
@testable import WanMap

/// Plan／PlanStore の「今ここ」まわりの検証。
/// - プレゼンスは作成から2時間で失効する（モデル判定と一覧からの除外）
/// - 新しい位置で置き換わり、重複しない（2時間の起点は置いた時刻のまま）
final class PlanStoreTests: XCTestCase {

    // MARK: - モデルの期限判定

    func testPlan_プレゼンスは2時間を超えると期限切れになる() {
        let expired = makePlan(isPresence: true, createdAt: Date().addingTimeInterval(-3 * 60 * 60))
        XCTAssertTrue(expired.isExpiredPresence)
        let fresh = makePlan(isPresence: true, createdAt: Date().addingTimeInterval(-1 * 60 * 60))
        XCTAssertFalse(fresh.isExpiredPresence)
    }

    func testPlan_通常の予定は古くても期限切れにならない() {
        let old = makePlan(isPresence: false, createdAt: Date().addingTimeInterval(-10 * 24 * 60 * 60))
        XCTAssertFalse(old.isExpiredPresence)
    }

    // MARK: - 一覧からの除外（保存しないサンプル経路）

    func testActivePlans_期限切れの今ここは除外され新しい今ここは残る() {
        let expired = makePlan(isPresence: true, createdAt: Date().addingTimeInterval(-3 * 60 * 60))
        let fresh = makePlan(isPresence: true, createdAt: Date().addingTimeInterval(-30 * 60))
        let normal = makePlan(isPresence: false)
        let store = PlanStore(samplePlans: [expired, fresh, normal])

        let activeIDs = Set(store.activePlans.map(\.id))
        XCTAssertFalse(activeIDs.contains(expired.id), "2時間を過ぎた「今ここ」が一覧に残っています")
        XCTAssertTrue(activeIDs.contains(fresh.id))
        XCTAssertTrue(activeIDs.contains(normal.id))
    }

    func testPrune_期限切れの今ここは保存データからも取り除かれる() {
        let expired = makePlan(isPresence: true, createdAt: Date().addingTimeInterval(-3 * 60 * 60))
        let normal = makePlan(isPresence: false)
        let store = PlanStore(samplePlans: [expired, normal])

        store.pruneExpiredPresence()

        XCTAssertFalse(store.plans.contains { $0.id == expired.id })
        XCTAssertTrue(store.plans.contains { $0.id == normal.id })
    }

    // MARK: - 自分の「今ここ」の配置と置き換え（端末保存経路）

    /// 端末保存を使うテストは、前後の状態を必ず空に戻す
    private func withPersistentStore(_ body: (PlanStore) -> Void) {
        let store = PlanStore()
        store.resetAllData()
        defer { store.resetAllData() }
        body(store)
    }

    func testOwnPresence_置くと取得でき座標が一致する() {
        withPersistentStore { store in
            store.placeOwnPresence(latitude: 35.0, longitude: 137.0)
            let presence = store.ownPresence
            XCTAssertNotNil(presence)
            XCTAssertEqual(presence?.latitude, 35.0)
            XCTAssertEqual(presence?.longitude, 137.0)
        }
    }

    func testOwnPresence_移動すると置き換わり起点時刻は変わらない() {
        withPersistentStore { store in
            store.placeOwnPresence(latitude: 35.0, longitude: 137.0)
            let placedAt = store.ownPresence?.createdAt

            store.moveOwnPresence(latitude: 35.1, longitude: 137.1)

            let moved = store.ownPresence
            XCTAssertEqual(moved?.latitude, 35.1)
            XCTAssertEqual(moved?.longitude, 137.1)
            XCTAssertEqual(moved?.createdAt, placedAt, "2時間の起点は最初に置いた時刻のままのはず")
            XCTAssertEqual(store.plans.filter { $0.isPresence }.count, 1, "置き換えで増えてはいけない")
        }
    }

    func testOwnPresence_もう一度置いても重複せず最新位置になる() {
        withPersistentStore { store in
            store.placeOwnPresence(latitude: 35.0, longitude: 137.0)
            store.placeOwnPresence(latitude: 35.2, longitude: 137.2)
            XCTAssertEqual(store.plans.filter { $0.isPresence }.count, 1)
            XCTAssertEqual(store.ownPresence?.latitude, 35.2)
            XCTAssertEqual(store.ownPresence?.longitude, 137.2)
        }
    }

    func testOwnPresence_消すと無くなる() {
        withPersistentStore { store in
            store.placeOwnPresence(latitude: 35.0, longitude: 137.0)
            store.clearOwnPresence()
            XCTAssertNil(store.ownPresence)
            XCTAssertTrue(store.plans.filter { $0.isPresence }.isEmpty)
        }
    }
}
