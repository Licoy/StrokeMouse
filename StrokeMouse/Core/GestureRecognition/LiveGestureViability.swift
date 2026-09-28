import CoreGraphics
import Foundation

/// Live drawing feedback state. Independent of end-of-stroke acceptance.
enum LiveViabilityState: String, Equatable, Sendable {
    /// Path is still short, hopeful, or already matches at least one candidate.
    case viable
    /// Path is long enough and no longer resembles any candidate with hope.
    case unlikely
}

/// Pure live-viability scoring for in-progress drawn strokes.
///
/// Uses optimistic similarity: raw shape keeps incomplete prefixes hopeful,
/// while a structurally compatible path also uses the canonical score that
/// end-of-stroke recognition would see. Final acceptance still remains in
/// `GestureRecognitionEvaluator`.
enum LiveGestureViability {
    struct Hysteresis: Equatable, Sendable {
        var state: LiveViabilityState = .viable
        var consecutiveUnlikelyEvals: Int = 0
    }

    /// Hope threshold below which a long path is considered unlikely.
    static func hopeThreshold(matchThreshold: Double) -> Double {
        let raw = matchThreshold - Constants.liveViabilityHopeThresholdOffset
        let range = Constants.liveViabilityHopeThresholdRange
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    /// Instantaneous viability for the current path against prepared templates.
    static func evaluate(
        path: [CGPoint],
        preparedTemplates: [TemplateMatcher.PreparedPath],
        minimumPathLength: CGFloat,
        matchThreshold: Double
    ) -> LiveViabilityState {
        guard path.count >= 2,
              path.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            return .viable
        }

        let length = PathSimplifier.pathLength(path)
        guard length.isFinite else { return .viable }
        guard length >= minimumPathLength else { return .viable }

        guard !preparedTemplates.isEmpty else { return .unlikely }

        let preparedStroke = TemplateMatcher.prepare(path)
        let hope = hopeThreshold(matchThreshold: matchThreshold)
        var bestHopeScore = 0.0
        var hasRecoverableCandidate = false

        for template in preparedTemplates {
            let match = TemplateMatcher.evaluate(
                stroke: preparedStroke,
                template: template
            )
            // A curve's current straight suffix can still turn later. Other
            // terminal overruns have already overshot the template structure.
            let recoverableCurveSuffix = match.structuralMismatch == .terminalOverrun
                && template.curveSignature?.isCurve == true
                && !template.flexibleSingleTurn
                && preparedStroke.curveSignature.map { strokeSignature in
                    template.curveSignature.map {
                        strokeSignature.hasExcessTerminalStraight(relativeTo: $0)
                    } ?? false
                } ?? false
            let baseHopeScore = max(match.shapeScore, match.score)
            let usesCurveMatching = template.curveSignature?.isCurve == true
                && !template.flexibleSingleTurn
            let prefixMeetsHope = usesCurveMatching && baseHopeScore < hope
                && TemplateMatcher.liveCurvePrefixMeetsThreshold(
                    stroke: preparedStroke,
                    template: template,
                    threshold: hope
                )
            // Raw shape keeps incomplete prefixes hopeful. Once structure is
            // compatible, also honor the canonical score used at release time.
            bestHopeScore = max(
                bestHopeScore,
                prefixMeetsHope ? hope : baseHopeScore
            )
            if match.structuralMismatch != .terminalOverrun || recoverableCurveSuffix {
                hasRecoverableCandidate = true
                if bestHopeScore >= hope { return .viable }
            }
        }

        if !hasRecoverableCandidate {
            return .unlikely
        }

        return bestHopeScore >= hope ? .viable : .unlikely
    }

    /// Debounce viable → unlikely; recover to viable immediately when hope returns.
    static func applyHysteresis(
        current: Hysteresis,
        observed: LiveViabilityState,
        consecutiveRequired: Int = Constants.liveViabilityUnlikelyHysteresisCount
    ) -> Hysteresis {
        let required = max(1, consecutiveRequired)
        switch observed {
        case .viable:
            return Hysteresis(state: .viable, consecutiveUnlikelyEvals: 0)
        case .unlikely:
            let count = current.consecutiveUnlikelyEvals + 1
            if count >= required {
                return Hysteresis(state: .unlikely, consecutiveUnlikelyEvals: count)
            }
            return Hysteresis(state: current.state, consecutiveUnlikelyEvals: count)
        }
    }
}
