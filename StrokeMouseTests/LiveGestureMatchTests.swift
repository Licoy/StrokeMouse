import CoreGraphics
import XCTest
@testable import StrokeMouse

final class LiveGestureMatchTests: XCTestCase {
    private let policy = GestureRecognitionPolicy.standard(minimumPathLength: 40)

    func testTrackerShowsMatchOnlyAfterItRepeats() {
        let id = UUID()
        var tracker = LiveGestureMatch.Tracker()

        tracker.observe(id, consecutiveRequired: 2)
        XCTAssertNil(tracker.shownProfileID)
        tracker.observe(id, consecutiveRequired: 2)
        XCTAssertEqual(tracker.shownProfileID, id)
        tracker.observe(id, consecutiveRequired: 2)
        XCTAssertEqual(tracker.shownProfileID, id)
    }

    func testTrackerClearsImmediatelyWhenMatchIsLost() {
        let id = UUID()
        var tracker = LiveGestureMatch.Tracker()
        tracker.observe(id, consecutiveRequired: 2)
        tracker.observe(id, consecutiveRequired: 2)

        tracker.observe(nil, consecutiveRequired: 2)
        XCTAssertNil(tracker.shownProfileID)
        // Losing the match also restarts the debounce.
        tracker.observe(id, consecutiveRequired: 2)
        XCTAssertNil(tracker.shownProfileID)
    }

    func testTrackerClearsStaleNameWhileANewMatchSettles() {
        let first = UUID()
        let second = UUID()
        var tracker = LiveGestureMatch.Tracker()
        tracker.observe(first, consecutiveRequired: 2)
        tracker.observe(first, consecutiveRequired: 2)

        tracker.observe(second, consecutiveRequired: 2)
        XCTAssertNil(tracker.shownProfileID)
        tracker.observe(second, consecutiveRequired: 2)
        XCTAssertEqual(tracker.shownProfileID, second)
    }

    func testAcceptedProfileMatchesReleaseEvaluation() {
        let right = GestureProfile(name: "Right", pattern: .freePath(PathTemplates.right))
        let left = GestureProfile(name: "Left", pattern: .freePath(PathTemplates.left))
        let path = Self.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0))

        let live = LiveGestureMatch.acceptedProfileID(
            path: path,
            profiles: [left, right],
            policy: policy
        )
        let release = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [left, right],
            policy: policy
        ).acceptedCandidate?.profile.id

        XCTAssertEqual(live, right.id)
        XCTAssertEqual(live, release)
    }

    func testNoAcceptedProfileForShortOrUnrelatedPath() {
        let right = GestureProfile(name: "Right", pattern: .freePath(PathTemplates.right))
        let short = Self.line(from: .zero, to: CGPoint(x: 20, y: 0))
        let reversed = Self.line(from: CGPoint(x: 200, y: 0), to: .zero)

        XCTAssertNil(LiveGestureMatch.acceptedProfileID(
            path: short,
            profiles: [right],
            policy: policy
        ))
        XCTAssertNil(LiveGestureMatch.acceptedProfileID(
            path: reversed,
            profiles: [right],
            policy: policy
        ))
    }

    func testAmbiguousCandidatesAreNotNamed() {
        let first = GestureProfile(name: "A", pattern: .freePath(PathTemplates.right))
        let second = GestureProfile(name: "B", pattern: .freePath(PathTemplates.right))
        let path = Self.line(from: .zero, to: CGPoint(x: 200, y: 0))

        XCTAssertNil(LiveGestureMatch.acceptedProfileID(
            path: path,
            profiles: [first, second],
            policy: policy
        ))
    }

    func testBadgeNamesTheActionReleaseWouldSelect() throws {
        var profile = GestureProfile(name: "Close Tab", pattern: .freePath(PathTemplates.right))

        XCTAssertNil(LiveGestureMatch.badge(for: nil, chordClicked: false))
        XCTAssertEqual(
            LiveGestureMatch.badge(for: nil, chordClicked: true),
            L10n.string("hud.secondaryActionBadge")
        )

        let primary = try XCTUnwrap(LiveGestureMatch.badge(for: profile, chordClicked: false))
        let missing = try XCTUnwrap(LiveGestureMatch.badge(for: profile, chordClicked: true))
        profile.secondaryAction = GestureAction.none
        let secondary = try XCTUnwrap(LiveGestureMatch.badge(for: profile, chordClicked: true))

        for badge in [primary, missing, secondary] {
            XCTAssertTrue(badge.contains("Close Tab"), badge)
        }
        XCTAssertEqual(Set([primary, missing, secondary]).count, 3)
    }

    func testBadgeTruncatesLongNames() throws {
        let name = String(repeating: "x", count: Constants.liveMatchBadgeNameLimit + 10)
        let profile = GestureProfile(name: name, pattern: .freePath(PathTemplates.right))

        let badge = try XCTUnwrap(LiveGestureMatch.badge(for: profile, chordClicked: false))
        XCTAssertFalse(badge.contains(name))
        XCTAssertTrue(badge.contains(
            String(repeating: "x", count: Constants.liveMatchBadgeNameLimit - 1) + "…"
        ))
    }

    private static func line(from start: CGPoint, to end: CGPoint, count: Int = 40) -> [CGPoint] {
        (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
    }
}
