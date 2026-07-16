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
    let decision: GestureEvaluationDecision
    let candidates: [GestureCandidateEvaluation]

    var acceptedCandidate: GestureCandidateEvaluation? {
        decision == .accepted ? candidates.first : nil
    }
}

/// Pure decision layer shared by global recognition and the diagnostic window.
enum GestureRecognitionEvaluator {
    static func shouldAccept(bestScore: Double, secondBestScore: Double?) -> Bool {
        guard bestScore >= Constants.freePathMatchThreshold else { return false }
        guard let secondBestScore else { return true }
        return bestScore - secondBestScore >= Constants.freePathMinLeadOverSecond
    }

    static func evaluate(
        path: [CGPoint],
        profiles: [GestureProfile],
        button: MouseTriggerButton,
        minimumLength: CGFloat
    ) -> GestureRecognitionEvaluation {
        guard path.count >= 2,
              path.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return result(.invalidPath, button: button) }

        let length = PathSimplifier.pathLength(path)
        guard length.isFinite else { return result(.invalidPath, button: button) }
        guard length >= minimumLength else {
            return result(.tooShort, button: button, pathLength: length)
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
            if lhs.score == rhs.score { return lhs.profile.id.uuidString < rhs.profile.id.uuidString }
            return lhs.score > rhs.score
        }

        guard let best = candidates.first else {
            return result(.noCandidates, button: button, pathLength: length)
        }
        guard best.score >= Constants.freePathMatchThreshold else {
            return result(.belowThreshold, button: button, pathLength: length, candidates: candidates)
        }
        let runnerUp = candidates.count >= 2 ? candidates[1].score : nil
        guard shouldAccept(bestScore: best.score, secondBestScore: runnerUp) else {
            return result(.ambiguous, button: button, pathLength: length, candidates: candidates)
        }
        return result(.accepted, button: button, pathLength: length, candidates: candidates)
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
        pathLength: CGFloat = 0,
        candidates: [GestureCandidateEvaluation] = []
    ) -> GestureRecognitionEvaluation {
        GestureRecognitionEvaluation(
            button: button,
            pathLength: pathLength,
            decision: decision,
            candidates: candidates
        )
    }
}
