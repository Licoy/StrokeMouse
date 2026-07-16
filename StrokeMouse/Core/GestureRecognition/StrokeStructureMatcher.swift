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
                templateSegments: templateExtraction.signature?.descriptors ?? []
            )
        }
        guard let templateSignature = templateExtraction.signature else {
            return Evaluation(
                cores: nil,
                mismatch: .invalidTemplate,
                strokeSegments: strokeSignature.descriptors,
                templateSegments: []
            )
        }
        if let mismatch = signatureMismatch(strokeSignature, templateSignature) {
            return Evaluation(
                cores: nil,
                mismatch: mismatch,
                strokeSegments: strokeSignature.descriptors,
                templateSegments: templateSignature.descriptors
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
            templateSegments: templateSignature.descriptors
        )
    }

    private static func signatureMismatch(
        _ stroke: StrokeStructureSignature,
        _ template: StrokeStructureSignature
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
}
