import CoreGraphics
import Foundation

enum GestureTestReplayFidelity: String, Equatable, Sendable {
    case exact
    case currentAlgorithmReevaluation
    case nonrecognition
    case unavailable
}

struct GestureTestReplayReport: Sendable {
    let entry: GestureTestLogEntry
    let fidelity: GestureTestReplayFidelity
    let evaluation: GestureRecognitionEvaluation?
    let unavailableReason: String?
    let decisionMatches: Bool?
    let winningProfileMatches: Bool?
    let scoreDelta: Double?
    let mismatchMatches: Bool?
    let winningSamplesMatch: Bool?
    let candidateScoresMatch: Bool?

    var hasMismatch: Bool {
        decisionMatches == false
            || winningProfileMatches == false
            || mismatchMatches == false
            || winningSamplesMatch == false
            || candidateScoresMatch == false
            || scoreDelta.map { abs($0) > 1e-12 } == true
    }
}

enum GestureTestLogValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case invalidRawPath
    case invalidMetrics
    case invalidPolicy
    case invalidMetadata
    case duplicateProfileID(UUID)
    case invalidCandidate(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return String(
                format: L10n.string(
                    "gestureTest.replay.validation.unsupportedSchema"
                ),
                locale: L10n.locale,
                version
            )
        case .invalidRawPath:
            return L10n.string("gestureTest.replay.validation.invalidRawPath")
        case .invalidMetrics:
            return L10n.string("gestureTest.replay.validation.invalidMetrics")
        case .invalidPolicy:
            return L10n.string("gestureTest.replay.validation.invalidPolicy")
        case .invalidMetadata:
            return L10n.string("gestureTest.replay.validation.invalidMetadata")
        case .duplicateProfileID(let id):
            return String(
                format: L10n.string(
                    "gestureTest.replay.validation.duplicateProfileID"
                ),
                locale: L10n.locale,
                id.uuidString
            )
        case .invalidCandidate(let id):
            return String(
                format: L10n.string(
                    "gestureTest.replay.validation.invalidCandidate"
                ),
                locale: L10n.locale,
                id.uuidString
            )
        }
    }
}

enum GestureTestLogReplay {
    static func replay(_ entry: GestureTestLogEntry) -> GestureTestReplayReport {
        do {
            try validate(entry)
        } catch {
            return unavailable(entry, reason: error.localizedDescription)
        }
        if entry.outcome == .cancelled || entry.decision == nil {
            return GestureTestReplayReport(
                entry: entry,
                fidelity: .nonrecognition,
                evaluation: nil,
                unavailableReason: "Cancelled before recognition",
                decisionMatches: nil,
                winningProfileMatches: nil,
                scoreDelta: nil,
                mismatchMatches: nil,
                winningSamplesMatch: nil,
                candidateScoresMatch: nil
            )
        }
        guard let recordedPolicy = entry.policy
        else {
            return unavailable(entry, reason: "Missing recognition policy")
        }
        guard entry.candidates.isEmpty || entry.evaluationTier != nil else {
            guard entry.schemaVersion < 6 else {
                return unavailable(entry, reason: "Missing recorded evaluation tier")
            }
            return replayLegacy(entry, policy: recordedPolicy)
        }
        guard entry.candidates.allSatisfy({ candidate in
            guard let paths = sourcePaths(for: candidate, schema: entry.schemaVersion),
                  !paths.isEmpty,
                  paths.allSatisfy({ $0.count >= 2 })
            else { return false }
            return true
        }) else {
            return unavailable(entry, reason: "Missing exact source templates")
        }

        let profiles = entry.candidates.compactMap { candidate in
            profile(
                for: candidate,
                activation: entry.activation ?? .mouse(
                    GestureTrigger(button: entry.selectedTrigger)
                ),
                tier: entry.evaluationTier ?? .global
            )
        }
        guard profiles.count == entry.candidates.count else {
            return unavailable(entry, reason: "Invalid source template collection")
        }
        let policy = GestureRecognitionPolicy(
            minimumPathLength: CGFloat(recordedPolicy.minimumPathLength),
            matchThreshold: recordedPolicy.matchThreshold,
            minimumLeadOverSecond: recordedPolicy.minimumLeadOverSecond,
            ambiguityResolution: recordedPolicy.ambiguityResolution ?? .reject
        )
        let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: entry.rawPath.map(\.cgPoint),
            profiles: profiles,
            policy: policy
        )
        let comparisons = compare(entry: entry, evaluation: evaluation)
        return GestureTestReplayReport(
            entry: entry,
            fidelity: entry.algorithmVersion == TemplateMatcher.algorithmVersion
                ? .exact
                : .currentAlgorithmReevaluation,
            evaluation: evaluation,
            unavailableReason: nil,
            decisionMatches: comparisons.decision,
            winningProfileMatches: comparisons.winner,
            scoreDelta: comparisons.maximumScoreDelta,
            mismatchMatches: comparisons.mismatches,
            winningSamplesMatch: comparisons.winningSamples,
            candidateScoresMatch: comparisons.scores
        )
    }

    static func validate(_ entry: GestureTestLogEntry) throws {
        guard (1...7).contains(entry.schemaVersion) else {
            throw GestureTestLogValidationError.unsupportedSchema(entry.schemaVersion)
        }
        guard entry.rawPath.allSatisfy({
            $0.x.isFinite && $0.y.isFinite
        }) else {
            throw GestureTestLogValidationError.invalidRawPath
        }
        guard [
            entry.metrics.pathLength,
            entry.metrics.width,
            entry.metrics.height,
        ].allSatisfy(\.isFinite) else {
            throw GestureTestLogValidationError.invalidMetrics
        }
        if entry.schemaVersion >= 6 {
            guard entry.source != nil,
                  entry.activation != nil,
                  entry.outcome != nil,
                  entry.algorithmVersion?.isEmpty == false,
                  entry.candidates.isEmpty || entry.evaluationTier != nil
            else {
                throw GestureTestLogValidationError.invalidMetadata
            }
            switch entry.outcome {
            case .recognition:
                guard entry.decision != nil,
                      let policy = entry.policy,
                      entry.schemaVersion < 7
                        || policy.ambiguityResolution != nil
                else {
                    throw GestureTestLogValidationError.invalidMetadata
                }
            case .cancelled:
                guard entry.decision == nil,
                      entry.policy == nil,
                      entry.candidates.isEmpty,
                      entry.acceptedProfileID == nil
                else {
                    throw GestureTestLogValidationError.invalidMetadata
                }
            case nil:
                throw GestureTestLogValidationError.invalidMetadata
            }
        }
        if let policy = entry.policy {
            guard policy.minimumPathLength.isFinite,
                  policy.minimumPathLength >= 0,
                  policy.matchThreshold.isFinite,
                  Constants.freePathMatchThresholdRange.contains(
                      policy.matchThreshold
                  ),
                  policy.minimumLeadOverSecond.isFinite,
                  (0...1).contains(policy.minimumLeadOverSecond)
            else {
                throw GestureTestLogValidationError.invalidPolicy
            }
        }
        var ids = Set<UUID>()
        for candidate in entry.candidates {
            guard ids.insert(candidate.profileID).inserted else {
                throw GestureTestLogValidationError.duplicateProfileID(
                    candidate.profileID
                )
            }
            guard candidate.score.isFinite, candidate.shapeScore.isFinite else {
                throw GestureTestLogValidationError.invalidCandidate(
                    candidate.profileID
                )
            }
            if let paths = candidate.sourceTemplatePaths {
                guard !paths.isEmpty,
                      paths.count <= DrawnGesture.maximumSampleCount,
                      paths.allSatisfy(validPath)
                else {
                    throw GestureTestLogValidationError.invalidCandidate(
                        candidate.profileID
                    )
                }
                if let index = candidate.winningTemplateIndex,
                   !paths.indices.contains(index)
                {
                    throw GestureTestLogValidationError.invalidCandidate(
                        candidate.profileID
                    )
                }
                if let evaluations = candidate.templateEvaluations,
                   evaluations.count != paths.count
                {
                    throw GestureTestLogValidationError.invalidCandidate(
                        candidate.profileID
                    )
                }
            }
            if entry.schemaVersion >= 6 {
                guard let paths = candidate.sourceTemplatePaths,
                      let index = candidate.winningTemplateIndex,
                      paths.indices.contains(index),
                      candidate.templateEvaluations?.count == paths.count
                else {
                    throw GestureTestLogValidationError.invalidCandidate(
                        candidate.profileID
                    )
                }
            }
            if let primary = candidate.sourceTemplatePath,
               !validPath(primary)
            {
                throw GestureTestLogValidationError.invalidCandidate(
                    candidate.profileID
                )
            }
        }
    }

    static func replay(contentsOf url: URL) throws -> [GestureTestReplayReport] {
        try GestureTestLogStore(logURL: url).readEntries().map(replay)
    }

    private static func profile(
        for candidate: GestureTestLogCandidate,
        activation: DrawActivation,
        tier: GestureTestLogEvaluationTier
    ) -> GestureProfile? {
        guard let paths = sourcePaths(for: candidate, schema: 6),
              let primary = paths.first
        else { return nil }
        return GestureProfile(
            id: candidate.profileID,
            name: candidate.profileName,
            input: .drawn(DrawnGesture(
                activation: activation,
                points: primary,
                additionalPaths: Array(paths.dropFirst())
            )),
            action: .none,
            scope: scope(for: tier)
        )
    }

    private static func scope(
        for tier: GestureTestLogEvaluationTier
    ) -> AppScope {
        switch tier {
        case .application:
            return .apps(["gesture-log-replay"])
        case .group:
            return .group(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        case .global:
            return .global
        }
    }

    private static func replayLegacy(
        _ entry: GestureTestLogEntry,
        policy: GestureTestLogRecognitionPolicy
    ) -> GestureTestReplayReport {
        guard entry.candidates.allSatisfy({
            sourcePaths(for: $0, schema: entry.schemaVersion) != nil
        }) else {
            return unavailable(entry, reason: "Missing exact source templates")
        }
        let profiles = entry.candidates.compactMap {
            legacyProfile(for: $0, trigger: entry.selectedTrigger)
        }
        guard profiles.count == entry.candidates.count else {
            return unavailable(entry, reason: "Invalid source template collection")
        }
        let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: entry.rawPath.map(\.cgPoint),
            profiles: profiles,
            policy: GestureRecognitionPolicy(
                minimumPathLength: CGFloat(policy.minimumPathLength),
                matchThreshold: policy.matchThreshold,
                minimumLeadOverSecond: policy.minimumLeadOverSecond,
                ambiguityResolution: policy.ambiguityResolution ?? .reject
            )
        )
        let comparisons = compare(entry: entry, evaluation: evaluation)
        return GestureTestReplayReport(
            entry: entry,
            fidelity: .currentAlgorithmReevaluation,
            evaluation: evaluation,
            unavailableReason: nil,
            decisionMatches: comparisons.decision,
            winningProfileMatches: comparisons.winner,
            scoreDelta: comparisons.maximumScoreDelta,
            mismatchMatches: comparisons.mismatches,
            winningSamplesMatch: nil,
            candidateScoresMatch: comparisons.scores
        )
    }

    private static func legacyProfile(
        for candidate: GestureTestLogCandidate,
        trigger: MouseTriggerButton
    ) -> GestureProfile? {
        guard let paths = sourcePaths(for: candidate, schema: 5),
              let primary = paths.first
        else { return nil }
        return GestureProfile(
            id: candidate.profileID,
            name: candidate.profileName,
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger(button: trigger)),
                points: primary,
                additionalPaths: Array(paths.dropFirst())
            )),
            action: .none,
            scope: .global
        )
    }

    private static func sourcePaths(
        for candidate: GestureTestLogCandidate,
        schema: Int
    ) -> [[CodablePoint]]? {
        if schema >= 6 { return candidate.sourceTemplatePaths }
        return candidate.sourceTemplatePath.map { [$0] }
    }

    private static func validPath(_ path: [CodablePoint]) -> Bool {
        path.count >= 2
            && path.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && zip(path, path.dropFirst()).contains { lhs, rhs in
                lhs.x != rhs.x || lhs.y != rhs.y
            }
    }

    private static func compare(
        entry: GestureTestLogEntry,
        evaluation: GestureRecognitionEvaluation
    ) -> (
        decision: Bool,
        winner: Bool,
        maximumScoreDelta: Double?,
        mismatches: Bool,
        winningSamples: Bool?,
        scores: Bool
    ) {
        let replayByID = Dictionary(
            uniqueKeysWithValues: evaluation.candidates.map {
                ($0.profile.id, $0)
            }
        )
        let sameIDs = Set(replayByID.keys)
            == Set(entry.candidates.map(\.profileID))
        let deltas = entry.candidates.flatMap { recorded -> [Double] in
            guard let replayed = replayByID[recorded.profileID] else { return [] }
            var values = [
                abs(replayed.score - recorded.score),
                abs(replayed.shapeScore - recorded.shapeScore),
            ]
            if let templates = recorded.templateEvaluations,
               templates.count == replayed.templateEvaluations.count
            {
                for (logged, current) in zip(
                    templates,
                    replayed.templateEvaluations
                ) {
                    values.append(abs(current.score - logged.finalScore))
                    values.append(abs(current.shapeScore - logged.shapeScore))
                }
            }
            return values
        }
        let mismatchMatches = sameIDs && entry.candidates.allSatisfy { recorded in
            guard let replayed = replayByID[recorded.profileID],
                  replayed.structuralMismatch == recorded.structuralMismatch
            else { return false }
            guard let templates = recorded.templateEvaluations else { return true }
            return templates.count == replayed.templateEvaluations.count
                && zip(templates, replayed.templateEvaluations).allSatisfy {
                    $0.structuralMismatch == $1.structuralMismatch
                }
        }
        let hasRecordedSampleIndexes = entry.candidates.allSatisfy {
            $0.winningTemplateIndex != nil
        }
        let sampleMatches = hasRecordedSampleIndexes
            ? sameIDs && entry.candidates.allSatisfy { recorded in
                replayByID[recorded.profileID]?.winningTemplateIndex
                    == recorded.winningTemplateIndex
            }
            : nil
        let maxDelta = sameIDs ? deltas.max() ?? 0 : nil
        return (
            entry.decision.map { evaluation.decision == $0 } ?? false,
            evaluation.acceptedCandidate?.profile.id == entry.acceptedProfileID,
            maxDelta,
            mismatchMatches,
            sampleMatches,
            sameIDs && deltas.allSatisfy { $0 <= 1e-12 }
        )
    }

    private static func unavailable(
        _ entry: GestureTestLogEntry,
        reason: String
    ) -> GestureTestReplayReport {
        GestureTestReplayReport(
            entry: entry,
            fidelity: .unavailable,
            evaluation: nil,
            unavailableReason: reason,
            decisionMatches: nil,
            winningProfileMatches: nil,
            scoreDelta: nil,
            mismatchMatches: nil,
            winningSamplesMatch: nil,
            candidateScoresMatch: nil
        )
    }
}
