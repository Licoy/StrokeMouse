import Foundation

enum DirectTrackpadMatch {
    case none
    case selected(TargetedGesture)
    case conflict([UUID])
}

struct DirectTrackpadGestureMatcher {
    func match(
        _ gesture: DirectTrackpadGesture,
        profiles: [GestureProfile],
        snapshot: GestureTargetSnapshot,
        rules: GestureAppRules = .empty
    ) -> DirectTrackpadMatch {
        let exact = profiles.filter { profile in
            guard profile.isEnabled,
                  case .trackpad(let configured) = profile.input
            else {
                return false
            }
            return configured == gesture
        }
        let targeted = GestureCandidateSelector.prepare(
            profiles: exact,
            snapshot: snapshot,
            inputKind: .touchGesture,
            rules: rules
        )
        // Only the most specific non-empty tier competes; several exact
        // matches inside that tier are a conflict.
        let preferredTier = targeted.map { GestureScopeTier($0.profile.scope) }.min()
        return resolve(targeted.filter {
            GestureScopeTier($0.profile.scope) == preferredTier
        })
    }

    private func resolve(
        _ matches: [TargetedGesture]
    ) -> DirectTrackpadMatch {
        switch matches.count {
        case 0:
            return .none
        case 1:
            return .selected(matches[0])
        default:
            return .conflict(matches.map(\.profile.id))
        }
    }
}
