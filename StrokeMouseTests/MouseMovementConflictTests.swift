import XCTest
@testable import StrokeMouse

final class MouseMovementConflictTests: XCTestCase {
    func testDraftScopeInputAndEnabledStateControlConflicts() {
        var drag = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)))
        let draw = GestureProfile(name: "Draw", input: .drawn(.init(
            activation: .mouse(.init(button: .right)), points: [])))
        XCTAssertTrue(MouseMovementConflict.hasConflict(draft: drag, scope: .global, profiles: [draw]))
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: drag, scope: .apps(["app"]), profiles: [draw]))
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: drag, scope: .global, profiles: [drag]))
        drag.isEnabled = false
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: drag, scope: .global, profiles: [draw]))
        drag.isEnabled = true
        drag.input = draw.input
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: drag, scope: .global, profiles: [draw]))
    }

    func testOnlyDefiniteSameTierScopeOverlapsBlockSaving() {
        var draft = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)))
        var other = draft
        other.id = UUID()
        other.scope = .apps(["a", "b"])
        XCTAssertTrue(MouseMovementConflict.hasConflict(draft: draft, scope: .apps(["b", "c"]), profiles: [other]))
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: draft, scope: .apps(["c"]), profiles: [other]))
        let group = UUID()
        other.scope = .group(group)
        XCTAssertTrue(MouseMovementConflict.hasConflict(draft: draft, scope: .group(group), profiles: [other]))
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: draft, scope: .group(UUID()), profiles: [other]))
        other.isEnabled = false
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: draft, scope: .group(group), profiles: [other]))
        draft.input = .mouseCombination(.init(action: .wheelUp))
        other.isEnabled = true
        XCTAssertFalse(MouseMovementConflict.hasConflict(draft: draft, scope: .group(group), profiles: [other]))
    }

    func testListEditsReportConflictsIncludingBetweenChangedProfiles() {
        let drag = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)))
        var draw = GestureProfile(name: "Draw", input: .drawn(.init(
            activation: .mouse(.init(button: .right)), points: [])))
        draw.isEnabled = false
        var wheel = GestureProfile(name: "Wheel", input: .mouseCombination(.init(action: .wheelUp)))
        wheel.isEnabled = false
        let library = [drag, draw, wheel]
        XCTAssertEqual(MouseMovementConflict.conflicts(of: draw, scope: .global, in: library).map(\.id), [])
        XCTAssertEqual(MouseMovementConflict.conflicts(afterChanging: [draw.id], in: library) { $0.isEnabled = true }
            .map(\.id), [drag.id])
        XCTAssertTrue(MouseMovementConflict.conflicts(afterChanging: [wheel.id], in: library) { $0.isEnabled = true }
            .isEmpty)
        // Moving both into the same app keeps them together, so they still clash.
        let moved = MouseMovementConflict.conflicts(afterChanging: [drag.id, draw.id], in: library) {
            $0.isEnabled = true
            $0.scope = .apps(["app"])
        }
        XCTAssertEqual(Set(moved.map(\.id)), [drag.id, draw.id])
        XCTAssertTrue(MouseMovementConflict.conflicts(afterChanging: [drag.id], in: library) {
            $0.scope = .apps(["app"])
        }.isEmpty)
    }

    func testExistingConflictsAndImportsDisableOnlyLaterClashes() {
        let drag = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)))
        let draw = GestureProfile(name: "Draw", input: .drawn(.init(
            activation: .mouse(.init(button: .right)), points: [])))
        var scoped = drag
        scoped.id = UUID()
        scoped.scope = .apps(["app"])
        XCTAssertEqual(MouseMovementConflict.conflictingIDs(in: [drag, draw, scoped]), [drag.id, draw.id])
        XCTAssertTrue(MouseMovementConflict.conflictingIDs(in: [drag, scoped]).isEmpty)

        var secondDrag = drag
        secondDrag.id = UUID()
        let result = MouseMovementConflict.disablingConflicts(in: [scoped, secondDrag, draw], existing: [drag])
        XCTAssertEqual(result.profiles.map(\.id), [scoped.id, secondDrag.id, draw.id])
        XCTAssertEqual(result.profiles.map(\.isEnabled), [true, false, false])
        XCTAssertEqual(result.disabled.map(\.id), [secondDrag.id, draw.id])
        let fresh = MouseMovementConflict.disablingConflicts(in: [secondDrag, draw], existing: [])
        XCTAssertEqual(fresh.profiles.map(\.isEnabled), [true, false])
    }
}
