import CoreGraphics
import Foundation

/// Builds normalized free-path templates for defaults and legacy direction migration.
enum PathTemplates {
    static func line(from: CGPoint, to: CGPoint, samples: Int = Constants.freePathSampleCount) -> [CodablePoint] {
        guard samples > 1 else { return [CodablePoint(from), CodablePoint(to)] }
        return (0..<samples).map { i in
            let t = CGFloat(i) / CGFloat(samples - 1)
            return CodablePoint(
                x: Double(from.x + (to.x - from.x) * t),
                y: Double(from.y + (to.y - from.y) * t)
            )
        }
    }

    /// Multi-segment polyline in unit square (y grows upward in template space; matching normalizes).
    static func polyline(_ corners: [CGPoint], samplesPerSegment: Int = 12) -> [CodablePoint] {
        guard corners.count >= 2 else { return corners.map(CodablePoint.init) }
        var points: [CodablePoint] = []
        for i in 0..<(corners.count - 1) {
            let a = corners[i]
            let b = corners[i + 1]
            let start = (i == 0) ? 0 : 1
            for s in start...samplesPerSegment {
                let t = CGFloat(s) / CGFloat(samplesPerSegment)
                points.append(CodablePoint(
                    x: Double(a.x + (b.x - a.x) * t),
                    y: Double(a.y + (b.y - a.y) * t)
                ))
            }
        }
        return points
    }

    static func fromDirections(_ directions: [Direction]) -> [CGPoint] {
        guard !directions.isEmpty else { return [] }
        var cursor = CGPoint(x: 0.5, y: 0.5)
        var points: [CGPoint] = [cursor]
        let step: CGFloat = 0.35
        for dir in directions {
            let delta: CGPoint
            switch dir {
            case .up: delta = CGPoint(x: 0, y: step)
            case .down: delta = CGPoint(x: 0, y: -step)
            case .left: delta = CGPoint(x: -step, y: 0)
            case .right: delta = CGPoint(x: step, y: 0)
            case .upLeft: delta = CGPoint(x: -step * 0.7, y: step * 0.7)
            case .upRight: delta = CGPoint(x: step * 0.7, y: step * 0.7)
            case .downLeft: delta = CGPoint(x: -step * 0.7, y: -step * 0.7)
            case .downRight: delta = CGPoint(x: step * 0.7, y: -step * 0.7)
            }
            cursor = CGPoint(x: cursor.x + delta.x, y: cursor.y + delta.y)
            points.append(cursor)
        }
        // Densify for matcher
        var dense: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            for s in 0..<8 {
                let t = CGFloat(s) / 8
                dense.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        dense.append(points[points.count - 1])
        return dense
    }

    // MARK: - Default shapes (unit-ish space)

    static var up: [CodablePoint] {
        line(from: CGPoint(x: 0.5, y: 0.1), to: CGPoint(x: 0.5, y: 0.9))
    }

    static var down: [CodablePoint] {
        line(from: CGPoint(x: 0.5, y: 0.9), to: CGPoint(x: 0.5, y: 0.1))
    }

    static var left: [CodablePoint] {
        line(from: CGPoint(x: 0.9, y: 0.5), to: CGPoint(x: 0.1, y: 0.5))
    }

    static var right: [CodablePoint] {
        line(from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5))
    }

    static var downLeft: [CodablePoint] {
        polyline([CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.1, y: 0.4)])
    }

    static var downRight: [CodablePoint] {
        polyline([CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.9, y: 0.4)])
    }

    static var upRight: [CodablePoint] {
        polyline([CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.9, y: 0.6)])
    }

    static var upLeft: [CodablePoint] {
        polyline([CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.1, y: 0.6)])
    }

    static var rightLeft: [CodablePoint] {
        polyline([CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.1, y: 0.5)])
    }

    /// Mountain / inverted-V peak (for tests and user-style freehand peaks).
    static var peak: [CodablePoint] {
        polyline([
            CGPoint(x: 0.1, y: 0.15),
            CGPoint(x: 0.5, y: 0.9),
            CGPoint(x: 0.9, y: 0.15),
        ])
    }
}
