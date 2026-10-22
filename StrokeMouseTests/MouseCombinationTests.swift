import CoreGraphics
import XCTest
@testable import StrokeMouse

final class MouseCombinationTests: XCTestCase {
    func testEdgesUseQuartzBoundsAcrossDisplaysAndRejectOutsidePoints() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                        CGRect(x: -1200, y: -900, width: 1200, height: 900)]
        XCTAssertTrue(MouseScreenEdge.top.contains(CGPoint(x: -600, y: -898), in: displays))
        XCTAssertTrue(MouseScreenEdge.bottom.contains(CGPoint(x: 500, y: 799), in: displays))
        XCTAssertTrue(MouseScreenEdge.left.contains(CGPoint(x: -1199, y: -400), in: displays))
        XCTAssertTrue(MouseScreenEdge.right.contains(CGPoint(x: 999, y: 400), in: displays))
        XCTAssertFalse(MouseScreenEdge.top.contains(CGPoint(x: 500, y: 4), in: displays))
        XCTAssertFalse(MouseScreenEdge.left.contains(CGPoint(x: -1201, y: -400), in: displays))
        XCTAssertFalse(MouseScreenEdge.top.contains(CGPoint(x: 1500, y: 0), in: displays))
    }

    func testCombinationsRoundTripThroughPortableProfile() throws {
        for edge in [nil] + MouseScreenEdge.allCases.map(Optional.some) {
            for action in MouseCombinationAction.allCases {
                let combo = MouseCombinationGesture(edge: edge, action: action)
                guard combo.isValid else { continue }
                let profile = GestureProfile(name: "Combo", input: .mouseCombination(combo), action: .none)
                let data = try JSONEncoder().encode(profile)
                XCTAssertEqual(try JSONDecoder().decode(GestureProfile.self, from: data), profile)
                XCTAssertFalse(profile.acceptsChordClick)
                XCTAssertFalse(GestureProfile.supportsSecondaryAction(profile.input))
            }
        }
        XCTAssertFalse(MouseCombinationGesture(action: .rightClick).isValid)
        XCTAssertFalse(MouseCombinationGesture(edge: .left, action: .leftClick).isValid)
    }

    func testWheelTapOnlyConsumesConfiguredDiscreteDirection() throws {
        let tap = MouseEventTap()
        tap.interceptsScroll = true
        tap.shouldCaptureScroll = { direction, _ in direction == .up }
        var count = 0
        tap.onEvent = { event, _ in if case .scroll = event { count += 1 } }
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: try wheel(1)) == nil)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: try wheel(-1)) != nil)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: try wheel(0)) != nil)
        XCTAssertEqual(count, 1)
        tap.interceptsScroll = false
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: try wheel(1)) != nil)
        XCTAssertEqual(count, 1)
    }

    func testWheelTapExcludesTrackpadMomentumAndSyntheticReplay() throws {
        let tap = MouseEventTap()
        tap.interceptsScroll = true
        tap.shouldCaptureScroll = { _, _ in XCTFail("Should bypass routing"); return true }
        let continuous = try wheel(1, units: .pixel)
        continuous.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: continuous) != nil)
        let momentum = try wheel(1)
        momentum.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: momentum) != nil)
        for marker in [CGScrollEventPoster.syntheticEventMarker, MouseEventTap.combinationReplayMarker] {
            let replay = try wheel(1)
            replay.setIntegerValueField(.eventSourceUserData, value: marker)
            XCTAssertTrue(tap.handle(type: .scrollWheel, event: replay) != nil)
        }
    }

    func testNativePixelWheelFromLogitechIsRecognized() throws {
        let tap = MouseEventTap()
        tap.interceptsScroll = true
        tap.shouldCaptureScroll = { _, _ in true }
        var directions: [MouseWheelDirection] = []
        tap.onEvent = { event, _ in
            if case .scroll(let direction, _, _) = event { directions.append(direction) }
        }
        // Recorded driver input: continuous=1, marker=0, pid=910, state=0.
        // Driver-origin events must not be rejected just because their PID is nonzero.
        for delta in [Int32(-1), Int32(1)] {
            let event = try wheel(delta, units: .pixel)
            event.setIntegerValueField(.eventSourceUnixProcessID, value: 910)
            XCTAssertTrue(tap.handle(type: .scrollWheel, event: event) == nil)
        }
        XCTAssertEqual(directions, [.down, .up])
    }

    func testSubLinePixelWheelUsesFixedOrPointDelta() throws {
        let tap = MouseEventTap()
        tap.interceptsScroll = true
        tap.shouldCaptureScroll = { _, _ in true }
        var directions: [MouseWheelDirection] = []
        tap.onEvent = { event, _ in
            if case .scroll(let direction, _, _) = event { directions.append(direction) }
        }
        let fixed = try wheel(0, units: .pixel)
        fixed.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.25)
        XCTAssertEqual(fixed.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: fixed) == nil)
        let point = try wheel(0, units: .pixel)
        point.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -1)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: point) == nil)
        XCTAssertEqual(directions, [.up, .down])
    }

    func testPixelDirectionOverridesStaleRoundedLineDirection() {
        XCTAssertEqual(MouseEventTap.combinationWheelDirection(
            ScrollEventSample(isContinuous: true, lineDeltaY: 1, fixedDeltaY: -0.25, pointDeltaY: -3)), -1)
        XCTAssertEqual(MouseEventTap.combinationWheelDirection(
            ScrollEventSample(isContinuous: true, lineDeltaY: -1, fixedDeltaY: 0.25, pointDeltaY: 3)), 1)
    }

    func testOppositeDirectionCannotTriggerThroughReversedSmoothReposts() throws {
        let tap = MouseEventTap()
        tap.interceptsScroll = true
        tap.shouldCaptureScroll = { direction, _ in direction == .up }
        var triggered = 0
        tap.onEvent = { event, _ in if case .scroll = event { triggered += 1 } }
        let down = try wheel(-1, units: .pixel)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: down) != nil)
        // A scroll utility reverses the down movement into many upward frames.
        // They remain scrolling data and cannot re-enter gesture recognition.
        var incorrectlyCaptured = 0
        for _ in 0..<60 {
            let repost = try wheel(1, units: .pixel, marker: -1600)
            if tap.handle(type: .scrollWheel, event: repost) == nil { incorrectlyCaptured += 1 }
        }
        XCTAssertEqual(incorrectlyCaptured, 0)
        XCTAssertEqual(triggered, 0)
        XCTAssertTrue(tap.handle(type: .scrollWheel, event: try wheel(1)) == nil)
        XCTAssertEqual(triggered, 1)
    }

    func testScrollReverseCannotMatchOppositeCombinationOnSecondTap() throws {
        let mouse = MouseEventTap()
        mouse.interceptsScroll = true
        mouse.shouldCaptureScroll = { direction, _ in direction == .up }
        var triggers = 0
        mouse.onEvent = { event, _ in if case .scroll = event { triggers += 1 } }
        MouseCombinationScrollBridge.shared.install(mouse)
        defer { MouseCombinationScrollBridge.shared.remove(mouse) }
        let scroll = ScrollEventTap()
        var snapshot = ScrollTapSnapshot()
        snapshot.enhancementEnabled = true
        snapshot.reverseMouseVertical = true
        scroll.snapshot = snapshot
        let down = try wheel(-1)
        XCTAssertTrue(scroll.handle(type: .scrollWheel, event: down) != nil)
        XCTAssertEqual(down.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        XCTAssertEqual(down.getIntegerValueField(.eventSourceUserData), MouseEventTap.combinationInspectedMarker)
        XCTAssertTrue(mouse.handle(type: .scrollWheel, event: down) != nil)
        XCTAssertEqual(triggers, 0)
    }

    func testPreciseWheelRepeatGateKeepsNotchesAndReversalsResponsive() {
        var gate = MouseCombinationWheelRepeatGate()
        XCTAssertTrue(gate.shouldExecute(action: .wheelUp, preciseTimestamp: 1))
        for frame in 1...10 {
            XCTAssertFalse(gate.shouldExecute(action: .wheelUp, preciseTimestamp: 1 + Double(frame) / 100))
        }
        XCTAssertTrue(gate.shouldExecute(action: .wheelUp, preciseTimestamp: 1.13))
        XCTAssertTrue(gate.shouldExecute(action: .wheelDown, preciseTimestamp: 1.14))
        XCTAssertTrue(gate.shouldExecute(action: .wheelUp, preciseTimestamp: nil))
        XCTAssertTrue(gate.shouldExecute(action: .wheelUp, preciseTimestamp: nil))
    }

    func testScrollEnhancementConsultsCombinationBeforeMutatingEvent() throws {
        let mouse = MouseEventTap()
        mouse.interceptsScroll = true
        var count = 0
        mouse.shouldCaptureScroll = { _, _ in true }
        mouse.onEvent = { event, _ in if case .scroll = event { count += 1 } }
        MouseCombinationScrollBridge.shared.install(mouse)
        defer { MouseCombinationScrollBridge.shared.remove(mouse) }
        let scroll = ScrollEventTap()
        let event = try wheel(1)
        XCTAssertTrue(scroll.handle(type: .scrollWheel, event: event) == nil)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
    }

    func testScrollReplayIsFreshEventWithOriginalDeltas() throws {
        let precise = try wheel(1, units: .pixel)
        precise.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.75)
        precise.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 3)
        precise.flags = .maskShift
        for original in [precise, try wheel(-2)] {
            // A swallowed tick's location goes stale while its target resolves.
            let stale = CGPoint(x: -31_337, y: -31_337)
            original.location = stale
            let replay = try XCTUnwrap(MouseEventTap.makeScrollReplayEvent(from: original))
            XCTAssertNotEqual(replay.location, stale)
            XCTAssertEqual(ScrollEventSample(event: replay), ScrollEventSample(event: original))
            XCTAssertEqual(
                replay.getIntegerValueField(.eventSourceUserData),
                MouseEventTap.combinationReplayMarker
            )
        }
    }

    private func wheel(_ delta: Int32, units: CGScrollEventUnit = .line, marker: Int64 = 0) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        source.userData = marker
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: source, units: units, wheelCount: 1,
                                         wheel1: delta, wheel2: 0, wheel3: 0))
        return event
    }
}
