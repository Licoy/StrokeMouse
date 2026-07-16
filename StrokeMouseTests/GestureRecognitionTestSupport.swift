import CoreGraphics
import Foundation
@testable import StrokeMouse

enum GestureRecognitionTestSupport {
    struct PeakVariation: CustomStringConvertible {
        let width: CGFloat
        let height: CGFloat
        let apexFraction: CGFloat
        let endpointOffset: CGFloat
        let jitter: CGFloat

        var description: String {
            "width=\(width), height=\(height), apex=\(apexFraction), "
                + "endpoint=\(endpointOffset), jitter=\(jitter)"
        }
    }

    struct LinearCongruentialGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(state >> 11) / 9_007_199_254_740_992
            return range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(unit)
        }
    }

    static let recordedNarrowPeak: [CGPoint] = [
        CGPoint(x: 0, y: 0.05048113408007771),
        CGPoint(x: 0.008705528292657447, y: 0.11717625637431325),
        CGPoint(x: 0.017411056585314895, y: 0.1838713786685488),
        CGPoint(x: 0.03537719561115647, y: 0.24857469621148076),
        CGPoint(x: 0.05486300489999532, y: 0.31295115772542464),
        CGPoint(x: 0.07434881418883416, y: 0.3773276192393685),
        CGPoint(x: 0.09383462347767302, y: 0.44170408075331236),
        CGPoint(x: 0.11332043276651188, y: 0.5060805422672563),
        CGPoint(x: 0.1328062420553507, y: 0.5704570037812001),
        CGPoint(x: 0.15229205134418952, y: 0.634833465295144),
        CGPoint(x: 0.1734745031610179, y: 0.6985899663516829),
        CGPoint(x: 0.20008435938081037, y: 0.7603632705587535),
        CGPoint(x: 0.22669421560060277, y: 0.8221365747658238),
        CGPoint(x: 0.25330407182039516, y: 0.8839098789728943),
        CGPoint(x: 0.2799139280401876, y: 0.9456831831799648),
        CGPoint(x: 0.3060900036554567, y: 0.9923712617025552),
        CGPoint(x: 0.3291062024529974, y: 0.9291709440323933),
        CGPoint(x: 0.3521224012505381, y: 0.8659706263622312),
        CGPoint(x: 0.3751386000480788, y: 0.8027703086920693),
        CGPoint(x: 0.3981547988456195, y: 0.7395699910219075),
        CGPoint(x: 0.4211709976431601, y: 0.6763696733517456),
        CGPoint(x: 0.4441871964407009, y: 0.6131693556815836),
        CGPoint(x: 0.4672033952382416, y: 0.5499690380114215),
        CGPoint(x: 0.49355184193791696, y: 0.4881452753988546),
        CGPoint(x: 0.5218504246073733, y: 0.42712711597399783),
        CGPoint(x: 0.5501490072768297, y: 0.3661089565491409),
        CGPoint(x: 0.578447589946286, y: 0.3050907971242841),
        CGPoint(x: 0.6067461726157424, y: 0.24407263769942716),
        CGPoint(x: 0.6350447552851987, y: 0.18305447827457044),
        CGPoint(x: 0.6633433379546549, y: 0.12203631884971367),
        CGPoint(x: 0.6916419206241113, y: 0.06101815942485678),
        CGPoint(x: 0.7199405032935676, y: 0),
    ]

    static let complexVertices = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0.2, y: 0.8),
        CGPoint(x: 0.4, y: 0.2), CGPoint(x: 0.6, y: 1),
        CGPoint(x: 0.8, y: 0.3), CGPoint(x: 1, y: 0.9),
        CGPoint(x: 1.2, y: 0.1),
    ]

    static func peak(
        _ variation: PeakVariation,
        sampleCount: Int = 81,
        timingExponent: CGFloat = 1
    ) -> [CGPoint] {
        (0..<sampleCount).map { index in
            let raw = CGFloat(index) / CGFloat(sampleCount - 1)
            let progress = CGFloat(pow(Double(raw), Double(timingExponent)))
            let isRising = progress <= 0.5
            let segmentProgress = isRising ? progress * 2 : (progress - 0.5) * 2
            let apex = CGPoint(x: variation.width * variation.apexFraction, y: variation.height)
            let start = isRising ? CGPoint.zero : apex
            let end = isRising ? apex : CGPoint(x: variation.width, y: variation.endpointOffset)
            let noise = sin(CGFloat(index) * 1.37) * variation.jitter
            return CGPoint(
                x: 100 + start.x + (end.x - start.x) * segmentProgress + noise * 0.3,
                y: 100 + start.y + (end.y - start.y) * segmentProgress + noise
            )
        }
    }

    static func randomPeak(using generator: inout LinearCongruentialGenerator) -> PeakVariation {
        PeakVariation(
            width: generator.nextCGFloat(in: 80...200),
            height: generator.nextCGFloat(in: 135...185),
            apexFraction: generator.nextCGFloat(in: 0.32...0.54),
            endpointOffset: generator.nextCGFloat(in: -14...14),
            jitter: generator.nextCGFloat(in: 0...5)
        )
    }

    static func appendingTail(
        to points: [CGPoint],
        lengthFraction: CGFloat,
        angleDegrees: CGFloat
    ) -> [CGPoint] {
        guard let end = points.last else { return points }
        let tailLength = PathSimplifier.pathLength(points) * lengthFraction
        let radians = angleDegrees * .pi / 180
        let tail = (1...12).map { index -> CGPoint in
            let progress = CGFloat(index) / 12
            return CGPoint(
                x: end.x + cos(radians) * tailLength * progress,
                y: end.y + sin(radians) * tailLength * progress
            )
        }
        return points + tail
    }

    static func rotate(_ points: [CGPoint], degrees: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        let radians = degrees * .pi / 180
        return points.map { point in
            let x = point.x - center.x
            let y = point.y - center.y
            return CGPoint(
                x: x * cos(radians) - y * sin(radians) + center.x,
                y: x * sin(radians) + y * cos(radians) + center.y
            )
        }
    }
}
