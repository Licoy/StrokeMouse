import XCTest
@testable import StrokeMouse

final class GestureRecognitionEvaluationTests: XCTestCase {
    func testAcceptsMatchingEnabledProfileForSelectedTrigger() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let matching = GestureProfile(
            name: "Peak",
            trigger: GestureTrigger(button: .middle),
            pattern: .freePath(template.map(CodablePoint.init))
        )
        let wrongTrigger = GestureProfile(
            name: "Wrong Trigger",
            trigger: GestureTrigger(button: .right),
            pattern: .freePath(template.map(CodablePoint.init))
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: [matching, wrongTrigger],
            button: .middle,
            minimumLength: 0
        )

        XCTAssertEqual(result.decision, .accepted)
        XCTAssertEqual(result.acceptedCandidate?.profile.id, matching.id)
        XCTAssertEqual(result.candidates.map(\.profile.id), [matching.id])
    }

    func testRejectsDisabledProfilesAndReportsNoCandidates() {
        let disabled = GestureProfile(
            name: "Disabled",
            isEnabled: false,
            pattern: .freePath(PathTemplates.up)
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: PathTemplates.up.map(\.cgPoint),
            profiles: [disabled],
            button: .right,
            minimumLength: 0
        )

        XCTAssertEqual(result.decision, .noCandidates)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testBelowThresholdCannotBeAcceptedEvenWithClearLead() {
        let peak = GestureProfile(
            name: "Peak",
            pattern: .freePath(GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init))
        )
        let horizontal = GestureProfile(
            name: "Horizontal",
            pattern: .freePath(PathTemplates.right)
        )
        let unrelated = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: -10),
            CGPoint(x: 10, y: 30),
            CGPoint(x: 40, y: 5),
        ]

        let result = GestureRecognitionEvaluator.evaluate(
            path: unrelated,
            profiles: [peak, horizontal],
            button: .right,
            minimumLength: 0
        )

        XCTAssertNotEqual(result.decision, .accepted)
        XCTAssertNil(result.acceptedCandidate)
    }

    func testStructuralMismatchIsAvailableForDiagnostics() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let profile = GestureProfile(
            name: "Peak",
            pattern: .freePath(template.map(CodablePoint.init))
        )
        let tailed = GestureRecognitionTestSupport.appendingTail(
            to: template,
            lengthFraction: 0.4,
            angleDegrees: 10
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: tailed,
            profiles: [profile],
            button: .right,
            minimumLength: 0
        )

        XCTAssertEqual(result.decision, .belowThreshold)
        XCTAssertNotNil(result.candidates.first?.structuralMismatch)
        XCTAssertGreaterThan(result.candidates.first?.shapeScore ?? 0, 0)
    }

    func testIdenticalTopCandidatesAreRejectedAsAmbiguous() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let profiles = ["First", "Second"].map { name in
            GestureProfile(
                name: name,
                pattern: .freePath(template.map(CodablePoint.init))
            )
        }

        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: profiles,
            button: .right,
            minimumLength: 0
        )

        XCTAssertEqual(result.decision, .ambiguous)
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertEqual(result.candidates.count, 2)
    }

    func testInvalidAndTooShortPathsHaveExplicitDecisions() {
        let invalid = GestureRecognitionEvaluator.evaluate(
            path: [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 1, y: 1)],
            profiles: [],
            button: .right,
            minimumLength: 40
        )
        let tooShort = GestureRecognitionEvaluator.evaluate(
            path: [CGPoint.zero, CGPoint(x: 5, y: 0)],
            profiles: [],
            button: .right,
            minimumLength: 40
        )

        XCTAssertEqual(invalid.decision, .invalidPath)
        XCTAssertEqual(tooShort.decision, .tooShort)
    }
}
