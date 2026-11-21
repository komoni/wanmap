import XCTest
@testable import WanMap

/// FriendService の純粋なヘルパー（単位2-4）。
/// pairId / requestId の組み立ては Firestore ルール側の約束と一致が必須
/// （friendships のドキュメントID、承認済み申請の引き方）。
final class FriendServiceTests: XCTestCase {

    func testPairIdは小さい方を前にそろえる() {
        XCTAssertEqual(FriendService.pairId("uid-b", "uid-a"), "uid-a_uid-b")
        XCTAssertEqual(FriendService.pairId("uid-a", "uid-b"), "uid-a_uid-b")
        XCTAssertEqual(FriendService.pairId("zzz", "aaa"), "aaa_zzz")
    }

    func testRequestIdは送り手_受け手の順() {
        XCTAssertEqual(FriendService.requestId(from: "alice", to: "bob"), "alice_bob")
        XCTAssertEqual(FriendService.requestId(from: "bob", to: "alice"), "bob_alice")
    }

    func testNormalizeCode() {
        XCTAssertEqual(FriendService.normalizeCode("  WAN-ABC234 "), "wan-abc234")
        XCTAssertEqual(FriendService.normalizeCode("@wan-abc234"), "wan-abc234")
        XCTAssertEqual(FriendService.normalizeCode("wan-abc234"), "wan-abc234")
    }
}
