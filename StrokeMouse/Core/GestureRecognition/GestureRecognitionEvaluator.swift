import CoreGraphics
import Foundation

/// Memoizes template preparation (resampling + structural extraction) per
/// profile. Preparation is a pure function of the complete path collection,
/// so edited or reused profile ids re-prepare in place.
final class GestureTemplateCache: @unchecked Sendable {
    static let shared = GestureTemplateCache()

    private struct Entry {
        let paths: [[CGPoint]]
        let preparedPaths: [TemplateMatcher.PreparedPath]
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    /// Well above any realistic profile count; wholesale reset on overflow
    /// keeps stale profile ids from accumulating forever.
    private let capacity = 128

    func prepared(id: UUID, points: [CGPoint]) -> TemplateMatcher.PreparedPath {
        preparedPaths(id: id, paths: [points])[0]
    }

    func preparedPaths(
        id: UUID,
        paths: [[CGPoint]]
    ) -> [TemplateMatcher.PreparedPath] {
        lock.lock()
        if let entry = entries[id], entry.paths == paths {
            lock.unlock()
            return entry.preparedPaths
        }
        lock.unlock()

        let prepared = paths.map { TemplateMatcher.prepare($0) }
        lock.lock()
        if entries[id] == nil, entries.count >= capacity {
            entries.removeAll(keepingCapacity: true)
        }
        entries[id] = Entry(paths: paths, preparedPaths: prepared)
        lock.unlock()
        return prepared
    }

}

enum GestureEvaluationDecision: String, Codable, Sendable {
    case accepted
    case invalidPath
    case tooShort
    case noCandidates
    case belowThreshold
    case ambiguous
}

enum GestureAmbiguityResolution: String, Codable, CaseIterable, Sendable {
    case reject
    case chooseBest
}

struct GestureRecognitionPolicy: Sendable, Equatable {
    let minimumPathLength: CGFloat
    let matchThreshold: Double
    let minimumLeadOverSecond: Double
    let ambiguityResolution: GestureAmbiguityResolution

    init(
        minimumPathLength: CGFloat,
        matchThreshold: Double = Constants.freePathMatchThreshold,
        minimumLeadOverSecond: Double = Constants.freePathMinLeadOverSecond,
        ambiguityResolution: GestureAmbiguityResolution = .reject
    ) {
        self.minimumPathLength = minimumPathLength
        self.matchThreshold = Self.normalizedMatchThreshold(matchThreshold)
        self.minimumLeadOverSecond = minimumLeadOverSecond
        self.ambiguityResolution = ambiguityResolution
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
    let structuralMismatch: TemplateMatcher.Mismatch?
    let diagnostics: TemplateMatcher.Diagnostics?
    let winningTemplateIndex: Int
    let templateEvaluations: [TemplateMatcher.Evaluation]

    init(
        profile: GestureProfile,
        score: Double,
        shapeScore: Double,
        structuralMismatch: TemplateMatcher.Mismatch?,
        diagnostics: TemplateMatcher.Diagnostics?,
        winningTemplateIndex: Int = 0,
        templateEvaluations: [TemplateMatcher.Evaluation] = []
    ) {
        self.profile = profile
        self.score = score
        self.shapeScore = shapeScore
        self.structuralMismatch = structuralMismatch
        self.diagnostics = diagnostics
        self.winningTemplateIndex = winningTemplateIndex
        self.templateEvaluations = templateEvaluations
    }
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
        guard policy.ambiguityResolution == .reject else { return true }
        guard let secondBestScore else { return true }
        return bestScore - secondBestScore >= policy.minimumLeadOverSecond
    }

    static func evaluate(
        path: [CGPoint],
        profiles: [GestureProfile],
        button: MouseTriggerButton,
        policy: GestureRecognitionPolicy
    ) -> GestureRecognitionEvaluation {
        evaluate(
            path: path,
            profiles: profiles,
            reportingButton: button,
            policy: policy
        ) { profile in
            guard case .drawn(let drawn) = profile.input,
                  case .mouse(let trigger) = drawn.activation
            else {
                return false
            }
            return trigger.button == button
        }
    }

    /// Profiles are expected to be filtered for the frozen target and input
    /// source before evaluation.
    static func evaluateDrawn(
        path: [CGPoint],
        profiles: [GestureProfile],
        policy: GestureRecognitionPolicy
    ) -> GestureRecognitionEvaluation {
        let includesDrawn: (GestureProfile) -> Bool = { profile in
            if case .drawn = profile.input { return true }
            return false
        }
        let tiers = GestureScopeTier.allCases.compactMap { tier -> [GestureProfile]? in
            let members = profiles.filter { GestureScopeTier($0.scope) == tier }
            return members.isEmpty ? nil : members
        }
        guard tiers.count > 1 else {
            return evaluate(
                path: path,
                profiles: profiles,
                reportingButton: .right,
                policy: policy,
                includes: includesDrawn
            )
        }

        // More specific tiers win; a tier that cannot accept falls through to
        // the next, keeping the most informative non-empty result.
        var result: GestureRecognitionEvaluation?
        for tierProfiles in tiers {
            let evaluation = evaluate(
                path: path,
                profiles: tierProfiles,
                reportingButton: .right,
                policy: policy,
                includes: includesDrawn
            )
            if result == nil || evaluation.decision != .noCandidates {
                result = evaluation
            }
            switch evaluation.decision {
            case .noCandidates, .belowThreshold:
                continue
            case .accepted, .invalidPath, .tooShort, .ambiguous:
                return evaluation
            }
        }
        return result ?? evaluate(
            path: path,
            profiles: profiles,
            reportingButton: .right,
            policy: policy,
            includes: includesDrawn
        )
    }

    private static func evaluate(
        path: [CGPoint],
        profiles: [GestureProfile],
        reportingButton button: MouseTriggerButton,
        policy: GestureRecognitionPolicy,
        includes: (GestureProfile) -> Bool
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

        let preparedStroke = TemplateMatcher.prepare(path)
        let candidates = profiles.compactMap { profile -> GestureCandidateEvaluation? in
            guard profile.isEnabled, includes(profile),
                  let templates = templatePaths(for: profile)
            else { return nil }
            let matches = GestureTemplateCache.shared.preparedPaths(
                id: profile.id,
                paths: templates
            ).map { template in
                TemplateMatcher.evaluate(
                    stroke: preparedStroke,
                    template: template
                )
            }
            guard let winner = matches.indices.max(by: { lhs, rhs in
                let left = matches[lhs]
                let right = matches[rhs]
                if left.score != right.score { return left.score < right.score }
                if left.shapeScore != right.shapeScore {
                    return left.shapeScore < right.shapeScore
                }
                return lhs > rhs
            }) else { return nil }
            let match = matches[winner]
            return GestureCandidateEvaluation(
                profile: profile,
                score: match.score,
                shapeScore: match.shapeScore,
                structuralMismatch: match.structuralMismatch,
                diagnostics: match.diagnostics,
                winningTemplateIndex: winner,
                templateEvaluations: matches
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

    private static func templatePaths(for profile: GestureProfile) -> [[CGPoint]]? {
        guard case .drawn(let drawn) = profile.input else { return nil }
        let paths = drawn.allPaths.map { $0.map(\.cgPoint) }
        return paths.allSatisfy { $0.count >= 2 } ? paths : nil
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
