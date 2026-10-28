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
}
