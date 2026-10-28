import Foundation

/// Only definite overlaps at the same scope tier block an editor draft.
/// Different app groups may overlap dynamically and are resolved by the runtime.
enum MouseMovementConflict {
    static func isDragScroll(_ input: GestureInput) -> Bool {
        guard case .mouseCombination(let combination) = input else { return false }
        return combination.edge == nil && combination.action == .dragScroll
    }

    static func hasConflict(draft: GestureProfile, scope: AppScope,
                            profiles: [GestureProfile]) -> Bool {
        guard draft.isEnabled, isMovement(draft.input) else { return false }
        return profiles.contains { other in
            other.id != draft.id && other.isEnabled && isMovement(other.input)
                && (isDragScroll(draft.input) || isDragScroll(other.input))
                && overlaps(scope, other.scope)
        }
    }

    private static func isMovement(_ input: GestureInput) -> Bool {
        if isDragScroll(input) { return true }
        guard case .drawn(let drawn) = input,
              case .mouse(let trigger) = drawn.activation else { return false }
        return trigger.button == .right
    }

    private static func overlaps(_ lhs: AppScope, _ rhs: AppScope) -> Bool {
        switch (lhs, rhs) {
        case (.global, .global): return true
        case (.apps(let a), .apps(let b)): return !Set(a).isDisjoint(with: b)
        case (.group(let a), .group(let b)): return a == b
        default: return false
        }
    }
}
