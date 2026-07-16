import XCTest
@testable import StrokeMouse

final class GestureMatchAcceptanceTests: XCTestCase {
    func testRejectsClearLeaderBelowFormalThreshold() {
        XCTAssertFalse(GestureEngine.shouldAcceptMatch(
            bestScore: 0.69,
            secondBestScore: 0.10
        ))
    }

    func testRejectsFormalMatchWithoutMinimumLead() {
        XCTAssertFalse(GestureEngine.shouldAcceptMatch(
            bestScore: 0.80,
            secondBestScore: 0.75
        ))
    }

    func testAcceptsFormalMatchWithClearLead() {
        XCTAssertTrue(GestureEngine.shouldAcceptMatch(
            bestScore: 0.80,
            secondBestScore: 0.70
        ))
    }
}
