import XCTest
@testable import StrokeMouse

final class GestureMatchAcceptanceTests: XCTestCase {
    func testRecognitionPolicyNormalizesConfiguredThreshold() {
        XCTAssertEqual(policy(threshold: 0.42).matchThreshold, 0.60)
        XCTAssertEqual(policy(threshold: 0.643).matchThreshold, 0.64)
        XCTAssertEqual(policy(threshold: 0.99).matchThreshold, 0.85)
        XCTAssertEqual(policy(threshold: .nan).matchThreshold, 0.70)
        XCTAssertEqual(
            GestureRecognitionPolicy.normalizedMatchThreshold(nil),
            0.70
        )
    }

    func testAcceptanceUsesConfiguredThreshold() {
        XCTAssertFalse(GestureRecognitionEvaluator.shouldAccept(
            bestScore: 0.65,
            secondBestScore: 0.10,
            policy: policy(threshold: 0.70)
        ))
        XCTAssertTrue(GestureRecognitionEvaluator.shouldAccept(
            bestScore: 0.65,
            secondBestScore: 0.10,
            policy: policy(threshold: 0.65)
        ))
    }

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

    private func policy(threshold: Double) -> GestureRecognitionPolicy {
        GestureRecognitionPolicy(
            minimumPathLength: 0,
            matchThreshold: threshold,
            minimumLeadOverSecond: Constants.freePathMinLeadOverSecond
        )
    }
}
