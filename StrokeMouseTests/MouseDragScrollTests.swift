import CoreGraphics
import XCTest
@testable import StrokeMouse

final class MouseDragScrollTests: XCTestCase {
    func testDeadzoneBothAxesNaturalDirectionAndPairedPhases() {
        var session = MouseDragScrollSession(origin: .zero, configuration: .init())
        XCTAssertNil(session.sample(CGPoint(x: 6, y: 6)))
        XCTAssertEqual(session.sample(CGPoint(x: 10, y: 0)), .init(x: 0, y: 0, phase: 1))
        XCTAssertEqual(session.sample(CGPoint(x: 20, y: 10)), .init(x: 10, y: -10, phase: 2))
        XCTAssertEqual(session.finish(cancelled: false), .init(x: 0, y: 0, phase: 4))
        XCTAssertNil(session.finish(cancelled: true))
    }

    func testFastFirstMovementKeepsDistanceBeyondDeadzoneAndFractionalRemainder() {
        var session = MouseDragScrollSession(origin: .zero, configuration: .init())
        XCTAssertEqual(session.sample(CGPoint(x: 20, y: 0)), .init(x: 10, y: 0, phase: 1))
        XCTAssertEqual(session.finish(cancelled: false), .init(x: 0, y: 0, phase: 4))
        var fractional = MouseDragScrollSession(origin: .zero, configuration: .init(sensitivity: 0.25))
        XCTAssertEqual(fractional.sample(CGPoint(x: 16, y: 0)), .init(x: 1, y: 0, phase: 1))
        XCTAssertEqual(fractional.sample(CGPoint(x: 18, y: 0)), .init(x: 1, y: 0, phase: 2))
    }

    func testFractionalPixelsAreRetainedAndReverseAffectsBothAxes() {
        var session = MouseDragScrollSession(origin: .zero,
            configuration: .init(sensitivity: 0.25, reversesDirection: true))
        XCTAssertNotNil(session.sample(CGPoint(x: 10, y: 0)))
        for offset in 1...3 { XCTAssertNil(session.sample(CGPoint(x: 10 + offset, y: offset))) }
        XCTAssertEqual(session.sample(CGPoint(x: 14, y: 4)), .init(x: -1, y: 1, phase: 2))
        XCTAssertEqual(session.finish(cancelled: true), .init(x: 0, y: 0, phase: 8))
    }

    func testShortPressHasNoPhaseAndConfigurationRejectsInvalidInput() throws {
        var session = MouseDragScrollSession(origin: .zero, configuration: .init())
        XCTAssertNil(session.finish(cancelled: false))
        for value in ["0", "-1", "4.01", "1e100"] {
            let data = Data("{\"sensitivity\":\(value)}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(MouseDragScrollConfiguration.self, from: data))
        }
        XCTAssertEqual(try JSONDecoder().decode(MouseDragScrollConfiguration.self, from: Data("{}".utf8)), .init())
        XCTAssertFalse(MouseCombinationGesture(edge: .top, action: .dragScroll).isValid)
        XCTAssertFalse(MouseCombinationGesture(action: .dragScroll, dragScroll: .init(sensitivity: .infinity)).isValid)
        let old = Data("{\"action\":\"wheelUp\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(MouseCombinationGesture.self, from: old).resolvedDragScrollConfiguration, .init())
    }

    func testMovementScopeOwnershipAndDuplicateConflict() {
        let globalDrag = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)))
        let globalDraw = GestureProfile(name: "Draw", pattern: .freePath(PathTemplates.up))
        var scopedDrag = globalDrag
        scopedDrag.id = UUID()
        scopedDrag.scope = .apps(["com.example.target"])
        var scopedDraw = globalDraw
        scopedDraw.id = UUID()
        scopedDraw.scope = scopedDrag.scope
        func targets(_ profiles: [GestureProfile]) -> [TargetedGesture] {
            profiles.map { TargetedGesture(profile: $0, target: .unavailable(.noElementAtPointer)) }
        }
        guard case .drag(let winner) = MouseDragScrollSelection.select(targets([globalDraw, scopedDrag]))
        else { return XCTFail("Scoped drag must own movement over global drawing") }
        XCTAssertEqual(winner.profile.id, scopedDrag.id)
        guard case .drawn = MouseDragScrollSelection.select(targets([globalDrag, scopedDraw]))
        else { return XCTFail("Scoped drawing must own movement over global drag") }
        guard case .conflict(let ids) = MouseDragScrollSelection.select(targets([globalDrag, globalDraw]))
        else { return XCTFail("Same-tier drag/draw must conflict") }
        XCTAssertEqual(ids, [globalDrag.id, globalDraw.id])
        guard case .conflict = MouseDragScrollSelection.select(targets([scopedDrag, scopedDrag]))
        else { return XCTFail("Duplicate drag must conflict") }
    }

    func testEventFactoryKeepsPixelDeltasPhaseMarkerAndZeroDeltaTerminal() throws {
        for phase: Int64 in [1, 2, 4, 8] {
            let event = try XCTUnwrap(CGScrollEventPoster.makeEvent(deltaY: 0, deltaX: 0, flags: [], phase: phase))
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), phase)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), CGScrollEventPoster.syntheticEventMarker)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        }
    }
}
