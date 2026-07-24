import CoreGraphics
import Foundation

struct StrokeStructureDescriptor: Sendable {
    let unitDirection: CGPoint
    let lengthFraction: CGFloat

    var angleDegrees: Double {
        atan2(Double(unitDirection.y), Double(unitDirection.x)) * 180 / .pi
    }
}

/// Non-compensating structural validation layered ahead of shape similarity.
enum StrokeStructureMatcher {
    private static let maximumContinuousTurnDegrees = 120.0
    private static let maximumOpposingTurnFraction = 0.25
    private static let maximumConcentratedTurnFraction = 0.95

    struct MonotonicTurn: Sendable {
        let sign: Double
        let magnitude: Double
    }

    enum Mismatch: String, Codable, Sendable, Equatable {
        case invalidStroke
        case invalidTemplate
        case terminalOverrun
        case segmentCount
        case segmentProportion
        case lineDirection
        case startDirection
        case turnDirection
        case turnAngle
        case endpointDirection
    }

    struct MatchingCores {
        let stroke: [CGPoint]
        let template: [CGPoint]
        let strokeSegments: [StrokeStructureDescriptor]
        let templateSegments: [StrokeStructureDescriptor]
    }

    struct Evaluation {
        let cores: MatchingCores?
        let mismatch: Mismatch?
        let strokeSegments: [StrokeStructureDescriptor]
        let templateSegments: [StrokeStructureDescriptor]
        let usesFlexibleSingleTurn: Bool
    }

    static func matchingCores(_ stroke: [CGPoint], _ template: [CGPoint]) -> MatchingCores? {
        evaluate(stroke, template).cores
    }

    static func evaluate(_ stroke: [CGPoint], _ template: [CGPoint]) -> Evaluation {
        let strokeExtraction = StrokeStructureExtractor.extract(stroke)
        let templateExtraction = StrokeStructureExtractor.extract(template)
        guard let strokeSignature = strokeExtraction.signature else {
            return Evaluation(
                cores: nil,
                mismatch: strokeExtraction.exceededTerminalBudget
                    ? .terminalOverrun
                    : .invalidStroke,
                strokeSegments: [],
                templateSegments: templateExtraction.signature?.descriptors ?? [],
                usesFlexibleSingleTurn: false
            )
        }
        guard let templateSignature = templateExtraction.signature else {
            return Evaluation(
                cores: nil,
                mismatch: .invalidTemplate,
                strokeSegments: strokeSignature.descriptors,
                templateSegments: [],
                usesFlexibleSingleTurn: false
            )
        }
        let flexibleSingleTurn = usesFlexibleSingleTurn(
            template,
            segments: templateSignature.descriptors
        )
        if let mismatch = signatureMismatch(
            strokeSignature,
            templateSignature,
            flexibleSingleTurn: flexibleSingleTurn
        ) {
            return Evaluation(
                cores: nil,
                mismatch: mismatch,
                strokeSegments: strokeSignature.descriptors,
                templateSegments: templateSignature.descriptors,
                usesFlexibleSingleTurn: flexibleSingleTurn
            )
        }

        let cores = MatchingCores(
            stroke: UnistrokeGeometry.trimmingTerminalFraction(
                stroke,
                strokeSignature.trimmedTerminalFraction
            ),
            template: UnistrokeGeometry.trimmingTerminalFraction(
                template,
                templateSignature.trimmedTerminalFraction
            ),
            strokeSegments: strokeSignature.descriptors,
            templateSegments: templateSignature.descriptors
        )
        return Evaluation(
            cores: cores,
            mismatch: nil,
            strokeSegments: strokeSignature.descriptors,
            templateSegments: templateSignature.descriptors,
            usesFlexibleSingleTurn: flexibleSingleTurn
        )
    }

    static func usesFlexibleSingleTurn(
        _ points: [CGPoint],
        segments: [StrokeStructureDescriptor]
    ) -> Bool {
        guard (2...4).contains(segments.count),
              let turn = monotonicTurn(in: segments),
              turn.magnitude <= StrokeSegmentReducer.degreesToRadians(
                maximumContinuousTurnDegrees
              ) else {
            return false
        }
        return hasDistributedTurn(points)
    }

    static func monotonicTurn(
        in segments: [StrokeStructureDescriptor]
    ) -> MonotonicTurn? {
        guard segments.count >= 2 else { return nil }

        var sign: Double?
        var magnitude = 0.0
        for (current, next) in zip(segments, segments.dropFirst()) {
            let turn = StrokeSegmentReducer.signedAngle(
                angle(of: next) - angle(of: current)
            )
            guard abs(turn) > 1e-8 else { continue }

            let currentSign = turn > 0 ? 1.0 : -1.0
            if let sign, sign != currentSign { return nil }
            sign = currentSign
            magnitude += abs(turn)
        }

        guard let sign, magnitude <= .pi + 1e-8 else { return nil }
        return MonotonicTurn(sign: sign, magnitude: magnitude)
    }

    private static func signatureMismatch(
        _ stroke: StrokeStructureSignature,
        _ template: StrokeStructureSignature,
        flexibleSingleTurn: Bool
    ) -> Mismatch? {
        if template.segments.count == 1 {
            guard stroke.segments.count == 1 else { return .segmentCount }
            let difference = StrokeSegmentReducer.angleDifference(
                stroke.segments[0].angle,
                template.segments[0].angle
            )
            return difference <= StrokeSegmentReducer.degreesToRadians(
                Constants.freePathLineAngleDegrees
            ) ? nil : .lineDirection
        }

        if flexibleSingleTurn {
            return singleTurnMismatch(stroke, template)
        }

        if template.segments.count <= 4 {
            return simpleSegmentMismatch(stroke, template)
        }

        let startDifference = StrokeSegmentReducer.angleDifference(
            stroke.startTangent,
            template.startTangent
        )
        let endDifference = StrokeSegmentReducer.angleDifference(
            stroke.endTangent,
            template.endTangent
        )
        guard startDifference <= StrokeSegmentReducer.degreesToRadians(
            Constants.freePathStartAngleDegrees
        ), endDifference <= StrokeSegmentReducer.degreesToRadians(
            Constants.freePathEndAngleDegrees
        ) else { return .endpointDirection }
        return nil
    }

    private static func singleTurnMismatch(
        _ stroke: StrokeStructureSignature,
        _ template: StrokeStructureSignature
    ) -> Mismatch? {
        guard let strokeTurn = monotonicTurn(in: stroke.descriptors),
              let templateTurn = monotonicTurn(in: template.descriptors)
        else { return .segmentCount }
        guard strokeTurn.sign == templateTurn.sign else { return .turnDirection }

        let difference = abs(strokeTurn.magnitude - templateTurn.magnitude)
        return difference <= StrokeSegmentReducer.degreesToRadians(
            Constants.freePathTurnAngleDegrees
        ) ? nil : .turnAngle
    }

    private static func simpleSegmentMismatch(
        _ stroke: StrokeStructureSignature,
        _ template: StrokeStructureSignature
    ) -> Mismatch? {
        guard stroke.segments.count == template.segments.count else { return .segmentCount }
        guard zip(stroke.descriptors, template.descriptors).allSatisfy({ stroke, template in
            Constants.freePathSegmentProportionRange.contains(
                stroke.lengthFraction / template.lengthFraction
            )
        }) else { return .segmentProportion }

        let startDifference = StrokeSegmentReducer.angleDifference(
            stroke.segments[0].angle,
            template.segments[0].angle
        )
        guard startDifference <= StrokeSegmentReducer.degreesToRadians(
            Constants.freePathStartAngleDegrees
        ) else { return .startDirection }

        for index in 0..<(template.segments.count - 1) {
            let strokeTurn = StrokeSegmentReducer.signedAngle(
                stroke.segments[index + 1].angle - stroke.segments[index].angle
            )
            let templateTurn = StrokeSegmentReducer.signedAngle(
                template.segments[index + 1].angle - template.segments[index].angle
            )
            guard strokeTurn * templateTurn > 0 else { return .turnDirection }
            let difference = StrokeSegmentReducer.angleDifference(strokeTurn, templateTurn)
            guard difference <= StrokeSegmentReducer.degreesToRadians(
                Constants.freePathTurnAngleDegrees
            ) else { return .turnAngle }
        }
        return nil
    }

    private static func angle(of descriptor: StrokeStructureDescriptor) -> Double {
        atan2(
            Double(descriptor.unitDirection.y),
            Double(descriptor.unitDirection.x)
        )
    }

    private static func hasDistributedTurn(_ points: [CGPoint]) -> Bool {
        let sampleCount = Constants.freePathSampleCount
        let chordOffset = 3
        guard points.count >= 3 else { return false }
        let sampled = PathSimplifier.resample(points, count: sampleCount)
        let headings = (0..<(sampled.count - chordOffset)).map { index in
            atan2(
                Double(sampled[index + chordOffset].y - sampled[index].y),
                Double(sampled[index + chordOffset].x - sampled[index].x)
            )
        }
        let turns = zip(headings, headings.dropFirst()).map {
            StrokeSegmentReducer.signedAngle($1 - $0)
        }
        let positive = turns.reduce(0.0) { $0 + max(0, $1) }
        let negative = turns.reduce(0.0) { $0 + max(0, -$1) }
        let dominant = max(positive, negative)
        let opposing = min(positive, negative)
        guard dominant >= StrokeSegmentReducer.degreesToRadians(
            Constants.freePathMergeAngleDegrees
        ), opposing <= dominant * maximumOpposingTurnFraction else {
            return false
        }

        let dominantTurns = turns.map { turn in
            positive >= negative ? max(0, turn) : max(0, -turn)
        }
        let windowSize = chordOffset * 2 + 1
        let mostConcentrated = dominantTurns.indices.map { start in
            dominantTurns[start..<min(start + windowSize, dominantTurns.count)].reduce(0, +)
        }.max() ?? dominant
        return mostConcentrated <= dominant * maximumConcentratedTurnFraction
    }
}
