import ApplicationServices
import XCTest
@testable import StrokeMouse

final class DirectTrackpadGestureMatcherTests: XCTestCase {
    func testApplicationSpecificMatchWinsOverGlobal() throws {
        let gesture = DirectTrackpadGesture.swipe(.three, .up)
        let global = profile(name: "Global", gesture: gesture)
        let scoped = profile(
            name: "Xcode",
            gesture: gesture,
            scope: .apps(["com.apple.dt.Xcode"])
        )
        let matcher = DirectTrackpadGestureMatcher()

        let result = matcher.match(
            gesture,
            profiles: [global, scoped],
            snapshot: snapshot(bundleIdentifier: "com.apple.dt.Xcode")
        )

        XCTAssertEqual(try selected(result).profile.id, scoped.id)
    }

    func testSamePriorityExactMatchesReportConflict() {
        let gesture = DirectTrackpadGesture.tap(.four, .single)
        let first = profile(name: "First", gesture: gesture)
        let second = profile(name: "Second", gesture: gesture)

        let result = DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: [first, second],
            snapshot: snapshot(bundleIdentifier: "com.apple.finder")
        )

        guard case .conflict(let ids) = result else {
            return XCTFail("Expected conflict")
        }
        XCTAssertEqual(ids, [first.id, second.id])
    }

    func testDisabledAndDifferentGesturesDoNotMatch() {
        let requested = DirectTrackpadGesture.rotate(.two, .clockwise)
        var disabled = profile(name: "Disabled", gesture: requested)
        disabled.isEnabled = false
        let other = profile(
            name: "Other",
            gesture: .rotate(.two, .counterclockwise)
        )

        let result = DirectTrackpadGestureMatcher().match(
            requested,
            profiles: [disabled, other],
            snapshot: snapshot(bundleIdentifier: "com.apple.finder")
        )

        guard case .none = result else {
            return XCTFail("Expected no match")
        }
    }

    private func profile(
        name: String,
        gesture: DirectTrackpadGesture,
        scope: AppScope = .global
    ) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .trackpad(gesture),
            scope: scope
        )
    }

    private func snapshot(bundleIdentifier: String) -> GestureTargetSnapshot {
        let context = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 42,
                bundleIdentifier: bundleIdentifier
            ),
            application: nil,
            window: GestureWindowTarget(
                element: AXUIElementCreateApplication(42)
            )
        )
        return GestureTargetSnapshot(
            frontmostWindow: .resolved(context),
            windowUnderPointer: .resolved(
                GestureTargetContext(
                    policy: .windowUnderPointer,
                    identity: context.identity,
                    application: nil,
                    window: context.window
                )
            )
        )
    }

    private func selected(
        _ result: DirectTrackpadMatch
    ) throws -> TargetedGesture {
        guard case .selected(let targeted) = result else {
            throw NSError(domain: "test", code: 1)
        }
        return targeted
    }
}
