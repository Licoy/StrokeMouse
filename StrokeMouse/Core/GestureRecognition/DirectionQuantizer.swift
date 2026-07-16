import CoreGraphics
import Foundation

enum DirectionQuantizer {
    /// Coordinate system for angle math.
    enum Axis: Sendable {
        /// AppKit / mathematical: Y grows upward.
        case yUp
        /// Quartz screen: Y grows downward.
        case yDown
    }

    /// Convert a stroke into a sequence of direction segments.
    static func quantize(
        _ points: [CGPoint],
        minSegmentLength: CGFloat = 12,
        useEightDirections: Bool = true,
        axis: Axis = .yUp
    ) -> [Direction] {
        guard points.count >= 2 else { return [] }

        var directions: [Direction] = []
        var anchor = points[0]

        for point in points.dropFirst() {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            let length = hypot(dx, dy)
            guard length >= minSegmentLength else { continue }

            // Convert to math angle where 0° = right, 90° = up.
            let mathDY = (axis == .yUp) ? dy : -dy
            let angle = atan2(mathDY, dx) * 180 / .pi // -180...180
            let direction = direction(fromDegrees: angle, eightWay: useEightDirections)
            if directions.last != direction {
                directions.append(direction)
            }
            anchor = point
        }

        return directions
    }

    static func direction(fromDegrees angle: Double, eightWay: Bool) -> Direction {
        var a = angle
        if a < 0 { a += 360 }

        if eightWay {
            let sector = Int((a + 22.5) / 45.0) % 8
            switch sector {
            case 0: return .right
            case 1: return .upRight
            case 2: return .up
            case 3: return .upLeft
            case 4: return .left
            case 5: return .downLeft
            case 6: return .down
            default: return .downRight
            }
        } else {
            let sector = Int((a + 45) / 90.0) % 4
            switch sector {
            case 0: return .right
            case 1: return .up
            case 2: return .left
            default: return .down
            }
        }
    }

    /// Levenshtein distance between two direction sequences.
    static func distance(_ a: [Direction], _ b: [Direction]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var prev = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    prev[j] + 1,
                    current[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = current
        }
        return prev[b.count]
    }

    /// Score 0...1 from direction edit distance.
    static func directionScore(_ a: [Direction], _ b: [Direction]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let dist = distance(a, b)
        let denom = max(a.count, b.count, 1)
        return max(0, 1 - Double(dist) / Double(denom))
    }
}
