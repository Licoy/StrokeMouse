import CoreGraphics
import Foundation

/// Live "release now" preview for in-progress drawn strokes.
///
/// Runs the same evaluator as release on the same frozen candidates, so the
/// HUD never names a gesture that releasing at that moment would not run.
/// Release still re-evaluates the final path; this is display only.
enum LiveGestureMatch {
    /// Debounces the named gesture so the badge does not flicker while the
    /// stroke passes through a match. A new match must repeat before it is
    /// shown; losing or changing the match clears the badge immediately, so
    /// a stale name never stays on screen.
    struct Tracker: Equatable, Sendable {
        private(set) var shownProfileID: UUID?
        private var pendingProfileID: UUID?
        private var pendingCount = 0

        mutating func observe(
            _ acceptedProfileID: UUID?,
            consecutiveRequired: Int = Constants.liveMatchStableEvalCount
        ) {
            guard let acceptedProfileID else {
                self = Tracker()
                return
            }
            guard acceptedProfileID != shownProfileID else { return }
            shownProfileID = nil
            if pendingProfileID == acceptedProfileID {
                pendingCount += 1
            } else {
                pendingProfileID = acceptedProfileID
                pendingCount = 1
            }
            if pendingCount >= max(1, consecutiveRequired) {
                shownProfileID = acceptedProfileID
                pendingProfileID = nil
                pendingCount = 0
            }
        }
    }

    /// Profile releasing now would run, or nil when release would not accept.
    static func acceptedProfileID(
        path: [CGPoint],
        profiles: [GestureProfile],
        policy: GestureRecognitionPolicy
    ) -> UUID? {
        GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: profiles,
            policy: policy
        ).acceptedCandidate?.profile.id
    }

    /// HUD badge text; a chord click names the action it selects at release.
    static func badge(
        for profile: GestureProfile?,
        chordClicked: Bool
    ) -> String? {
        guard let profile else {
            return chordClicked ? L10n.string("hud.secondaryActionBadge") : nil
        }
        let name = displayName(profile.name)
        let key: String
        if !chordClicked {
            key = "hud.liveMatchBadge"
        } else if profile.secondaryAction != nil {
            key = "hud.liveMatchSecondaryBadge"
        } else {
            key = "hud.liveMatchNoSecondaryBadge"
        }
        return String(format: L10n.string(key), locale: L10n.locale, name)
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = Constants.liveMatchBadgeNameLimit
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }
}
