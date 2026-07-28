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
        snapshot: GestureTargetSnapshot
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
            snapshot: snapshot
        )
        let applicationSpecific = targeted.filter {
            if case .apps = $0.profile.scope { return true }
            return false
        }
        return resolve(
            applicationSpecific.isEmpty ? targeted : applicationSpecific
        )
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
