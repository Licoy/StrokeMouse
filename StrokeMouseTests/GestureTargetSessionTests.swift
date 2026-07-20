import XCTest
@testable import StrokeMouse

@MainActor
final class GestureTargetSessionTests: XCTestCase {
    func testCapturesOnceAtButtonDownAndConsumesFrozenSnapshotAtButtonUp() throws {
        let capturedWindow = GestureWindowTarget(
            element: AXUIElementCreateApplication(101)
        )
        let frozen = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 101,
                bundleIdentifier: "com.apple.Safari"
            ),
            application: nil,
            window: capturedWindow
        )
        let expected = GestureTargetSnapshot(
            frontmostWindow: .resolved(frozen),
            windowUnderPointer: .unavailable(.targetNotCaptured(.windowUnderPointer))
        )
        let capturer = SpyGestureTargetCapturer(snapshot: expected)
        let session = GestureStrokeTargetSession(capturer: capturer)
        let profiles = [
            GestureProfile(
                name: "Active",
                pattern: .freePath(PathTemplates.up),
                targetPolicy: .frontmostWindow
            ),
            GestureProfile(
                name: "Hover",
                pattern: .freePath(PathTemplates.down),
                targetPolicy: .windowUnderPointer
            ),
        ]
        let downLocation = CGPoint(x: 123, y: 456)

        session.handleButtonDown(profiles: profiles, at: downLocation)
        let consumed = try XCTUnwrap(session.takeAtButtonUp())

        XCTAssertEqual(capturer.calls.count, 1)
        XCTAssertEqual(capturer.calls[0].policies, Set(GestureTargetPolicy.allCases))
        XCTAssertEqual(capturer.calls[0].location, downLocation)
        XCTAssertTrue(consumed.frontmostWindow.context?.window === capturedWindow)
        XCTAssertNil(session.takeAtButtonUp())
    }

    func testCancelClearsSnapshotAndOnlyAnotherButtonDownRecaptures() {
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .unavailable(.noFrontmostApplication),
            windowUnderPointer: .unavailable(.noElementAtPointer)
        )
        let capturer = SpyGestureTargetCapturer(snapshot: snapshot)
        let session = GestureStrokeTargetSession(capturer: capturer)
        let profile = GestureProfile(
            name: "Active",
            pattern: .freePath(PathTemplates.up)
        )

        session.handleButtonDown(profiles: [profile], at: .zero)
        session.cancel()

        XCTAssertNil(session.takeAtButtonUp())
        XCTAssertEqual(capturer.calls.count, 1)

        session.handleButtonDown(profiles: [profile], at: CGPoint(x: 1, y: 2))

        XCTAssertEqual(capturer.calls.count, 2)
    }
}

@MainActor
private final class SpyGestureTargetCapturer: GestureTargetCapturing {
    struct Call {
        let policies: Set<GestureTargetPolicy>
        let location: CGPoint
    }

    let snapshot: GestureTargetSnapshot
    private(set) var calls: [Call] = []

    init(snapshot: GestureTargetSnapshot) {
        self.snapshot = snapshot
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        calls.append(Call(policies: policies, location: quartzLocation))
        return snapshot
    }
}
