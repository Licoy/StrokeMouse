import CoreGraphics
import Foundation

/// Live drawing feedback state. Independent of end-of-stroke acceptance.
enum LiveViabilityState: String, Equatable, Sendable {
    /// Path is still short or shape-similar to at least one candidate.
    case viable
    /// Path is long enough and no longer resembles any candidate with hope.
    case unlikely
}

/// Pure live-viability scoring for in-progress drawn strokes.
///
/// Uses shape-only similarity (ignores most structural hard rejects) so
/// incomplete but correct prefixes stay viable. End-of-stroke recognition
/// still uses `GestureRecognitionEvaluator` unchanged.
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
        var bestShape = 0.0
        var sawNonTerminalOverrun = false

        for template in preparedTemplates {
            let match = TemplateMatcher.evaluate(
                stroke: preparedStroke,
                template: template
            )
            if match.shapeScore > bestShape {
                bestShape = match.shapeScore
            }
            // terminalOverrun is the one structural miss that is irreversible
            // mid-stroke (path already overshot the template end).
            if match.structuralMismatch != .terminalOverrun {
                sawNonTerminalOverrun = true
            }
        }

        if !sawNonTerminalOverrun {
            return .unlikely
        }

        let hope = hopeThreshold(matchThreshold: matchThreshold)
        return bestShape >= hope ? .viable : .unlikely
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
