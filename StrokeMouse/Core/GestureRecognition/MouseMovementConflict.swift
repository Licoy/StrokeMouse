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
        !conflicts(of: draft, scope: scope, in: profiles).isEmpty
    }

    /// Enabled profiles that would share movement input with `draft` at `scope`.
    static func conflicts(of draft: GestureProfile, scope: AppScope,
                          in profiles: [GestureProfile]) -> [GestureProfile] {
        guard draft.isEnabled, isMovement(draft.input) else { return [] }
        return profiles.filter { other in
            other.id != draft.id && other.isEnabled && isMovement(other.input)
                && (isDragScroll(draft.input) || isDragScroll(other.input))
                && overlaps(scope, other.scope)
        }
    }

    /// Conflicts a batch edit would create, including those between edited profiles.
    static func conflicts(afterChanging ids: Set<UUID>, in profiles: [GestureProfile],
                          _ change: (inout GestureProfile) -> Void) -> [GestureProfile] {
        let updated = profiles.map { profile in
            var profile = profile
            if ids.contains(profile.id) { change(&profile) }
            return profile
        }
        var found: [GestureProfile] = []
        for profile in updated where ids.contains(profile.id) {
            for other in conflicts(of: profile, scope: profile.scope, in: updated)
            where !found.contains(where: { $0.id == other.id }) {
                found.append(other)
            }
        }
        return found
    }

    /// Enabled profiles already in a definite conflict, e.g. after a backup restore.
    static func conflictingIDs(in profiles: [GestureProfile]) -> Set<UUID> {
        Set(profiles.filter { hasConflict(draft: $0, scope: $0.scope, profiles: profiles) }.map(\.id))
    }

    /// Keeps incoming order and disables each profile that would conflict with
    /// the existing library or an earlier incoming profile.
    static func disablingConflicts(
        in incoming: [GestureProfile], existing: [GestureProfile]
    ) -> (profiles: [GestureProfile], disabled: [GestureProfile]) {
        var accepted = existing
        var disabled: [GestureProfile] = []
        let profiles = incoming.map { profile in
            var profile = profile
            if hasConflict(draft: profile, scope: profile.scope, profiles: accepted) {
                profile.isEnabled = false
                disabled.append(profile)
            }
            accepted.append(profile)
            return profile
        }
        return (profiles, disabled)
    }

    /// Names the first two conflicting profiles, then counts the rest.
    static func displayNames(_ profiles: [GestureProfile]) -> String {
        var names = profiles.prefix(2).map {
            String(format: L10n.string("common.quotedName"), locale: L10n.locale, $0.name)
        }
        if profiles.count > 2 {
            names.append(String(format: L10n.string("common.moreCount"), locale: L10n.locale, profiles.count - 2))
        }
        let formatter = ListFormatter()
        formatter.locale = L10n.locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    static func conflictMessage(_ profiles: [GestureProfile]) -> String {
        String(format: L10n.string("editor.saveMovementConflict"), locale: L10n.locale, displayNames(profiles))
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
