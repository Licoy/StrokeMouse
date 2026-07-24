import CoreGraphics
import Foundation

enum GestureEvaluationDecision: String, Codable, Sendable {
    case accepted
    case invalidPath
    case tooShort
    case noCandidates
    case belowThreshold
    case ambiguous
}

struct GestureRecognitionPolicy: Sendable, Equatable {
    let minimumPathLength: CGFloat
    let matchThreshold: Double
    let minimumLeadOverSecond: Double

    init(
        minimumPathLength: CGFloat,
        matchThreshold: Double = Constants.freePathMatchThreshold,
        minimumLeadOverSecond: Double = Constants.freePathMinLeadOverSecond
    ) {
        self.minimumPathLength = minimumPathLength
        self.matchThreshold = Self.normalizedMatchThreshold(matchThreshold)
        self.minimumLeadOverSecond = minimumLeadOverSecond
    }

    static func standard(minimumPathLength: CGFloat) -> Self {
        Self(minimumPathLength: minimumPathLength)
    }

    static func normalizedMatchThreshold(_ value: Double?) -> Double {
        guard let value, value.isFinite else {
            return Constants.freePathMatchThreshold
        }
        let range = Constants.freePathMatchThresholdRange
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let roundedPercentage = (clamped * 100).rounded()
        return min(range.upperBound, max(range.lowerBound, roundedPercentage / 100))
    }
}

struct GestureCandidateEvaluation: Sendable {
    let profile: GestureProfile
    let score: Double
    let shapeScore: Double
    let structuralMismatch: StrokeStructureMatcher.Mismatch?
    let diagnostics: TemplateMatcher.Diagnostics?
}

struct GestureRecognitionEvaluation: Sendable {
    let button: MouseTriggerButton
    let pathLength: CGFloat
    let policy: GestureRecognitionPolicy
    let decision: GestureEvaluationDecision
    let candidates: [GestureCandidateEvaluation]

    var acceptedCandidate: GestureCandidateEvaluation? {
        decision == .accepted ? candidates.first : nil
    }
}

/// Pure decision layer shared by global recognition and the diagnostic window.
enum GestureRecognitionEvaluator {
    static func shouldAccept(
        bestScore: Double,
        secondBestScore: Double?,
        policy: GestureRecognitionPolicy = .standard(minimumPathLength: 0)
    ) -> Bool {
        guard bestScore >= policy.matchThreshold else { return false }
        guard let secondBestScore else { return true }
        return bestScore - secondBestScore >= policy.minimumLeadOverSecond
    }

    static func evaluate(
        path: [CGPoint],
        profiles: [GestureProfile],
        button: MouseTriggerButton,
        policy: GestureRecognitionPolicy
    ) -> GestureRecognitionEvaluation {
        guard path.count >= 2,
              path.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return result(.invalidPath, button: button, policy: policy) }

        let length = PathSimplifier.pathLength(path)
        guard length.isFinite else {
            return result(.invalidPath, button: button, policy: policy)
        }
        guard length >= policy.minimumPathLength else {
            return result(.tooShort, button: button, policy: policy, pathLength: length)
        }

        let candidates = profiles.compactMap { profile -> GestureCandidateEvaluation? in
            guard profile.isEnabled, profile.trigger.button == button,
                  let template = templatePoints(for: profile)
            else { return nil }
            let match = TemplateMatcher.evaluate(path, template)
            return GestureCandidateEvaluation(
                profile: profile,
                score: match.score,
                shapeScore: match.shapeScore,
                structuralMismatch: match.structuralMismatch,
                diagnostics: match.diagnostics
            )
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.shapeScore != rhs.shapeScore { return lhs.shapeScore > rhs.shapeScore }
            return lhs.profile.id.uuidString < rhs.profile.id.uuidString
        }

        guard let best = candidates.first else {
            return result(.noCandidates, button: button, policy: policy, pathLength: length)
        }
        guard best.score >= policy.matchThreshold else {
            return result(
                .belowThreshold,
                button: button,
                policy: policy,
                pathLength: length,
                candidates: candidates
            )
        }
        let runnerUp = candidates.count >= 2 ? candidates[1].score : nil
        guard shouldAccept(
            bestScore: best.score,
            secondBestScore: runnerUp,
            policy: policy
        ) else {
            return result(
                .ambiguous,
                button: button,
                policy: policy,
                pathLength: length,
                candidates: candidates
            )
        }
        return result(
            .accepted,
            button: button,
            policy: policy,
            pathLength: length,
            candidates: candidates
        )
    }

    private static func templatePoints(for profile: GestureProfile) -> [CGPoint]? {
        let points: [CGPoint]
        switch profile.pattern {
        case .freePath(let template):
            points = template.map(\.cgPoint)
        case .directions(let directions):
            points = PathTemplates.fromDirections(directions)
        }
        return points.count >= 2 ? points : nil
    }

    private static func result(
        _ decision: GestureEvaluationDecision,
        button: MouseTriggerButton,
        policy: GestureRecognitionPolicy,
        pathLength: CGFloat = 0,
        candidates: [GestureCandidateEvaluation] = []
    ) -> GestureRecognitionEvaluation {
        GestureRecognitionEvaluation(
            button: button,
            pathLength: pathLength,
            policy: policy,
            decision: decision,
            candidates: candidates
        )
    }
}
