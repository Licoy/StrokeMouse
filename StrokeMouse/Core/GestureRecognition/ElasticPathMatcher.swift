import CoreGraphics
import Foundation

/// Arc-length profile of one unistroke: resampled, lightly smoothed, normalized
/// points plus the local tangent heading at each point.
struct ElasticPathProfile: Sendable {
    let points: [CGPoint]
    let headings: [Double]

    /// `sampleCount` below the matcher default gives a coarser profile for
    /// the live HUD; the tangent span keeps the same share of arc length.
    init?(_ input: [CGPoint], sampleCount count: Int = ElasticPathMatcher.sampleCount) {
        guard let sampled = UnistrokeGeometry.resampledPath(input, count: count),
              let normalized = Self.normalized(
                PathSimplifier.resample(Self.smoothed(sampled), count: count)
              ) else { return nil }
        points = normalized
        let offset = max(
            1,
            ElasticPathMatcher.tangentOffset * count / ElasticPathMatcher.sampleCount
        )
        headings = normalized.indices.map { index in
            let start = normalized[max(0, index - offset)]
            let end = normalized[min(normalized.count - 1, index + offset)]
            return atan2(Double(end.y - start.y), Double(end.x - start.x))
        }
    }

    /// Three-point moving average with fixed endpoints; removes sampling
    /// jitter without moving where the stroke starts or ends.
    private static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        return points.indices.map { index in
            guard index > 0, index < points.count - 1 else { return points[index] }
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            return CGPoint(
                x: (previous.x + current.x + next.x) / 3,
                y: (previous.y + current.y + next.y) / 3
            )
        }
    }

    /// Centroid-centered normalization. Paths that are thin along their own
    /// principal axis (lines, including diagonal ones) keep their aspect ratio
    /// so direction stays meaningful; clearly 2D paths are scaled per axis so
    /// a wider or taller redraw of the same shape still aligns. The transition
    /// is smooth to avoid a score cliff at the boundary.
    private static func normalized(_ points: [CGPoint]) -> [CGPoint]? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        let width = maxX - minX
        let height = maxY - minY
        let major = max(width, height)
        guard major.isFinite, major > 1e-8 else { return nil }

        let lower = ElasticPathMatcher.anisotropicThicknessRange.lowerBound
        let upper = ElasticPathMatcher.anisotropicThicknessRange.upperBound
        let progress = min(1, max(0, (principalThickness(points) - lower) / (upper - lower)))
        let blend = progress * progress * (3 - 2 * progress)
        let minorScale = major * (1 - blend) + min(width, height) * blend
        let scaleX = width < height ? minorScale : major
        let scaleY = width < height ? major : minorScale

        let scaled = points.map { CGPoint(x: $0.x / scaleX, y: $0.y / scaleY) }
        let center = UnistrokeGeometry.centroid(scaled)
        return scaled.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y) }
    }

    /// Extent across the principal axis relative to the extent along it:
    /// near 0 for a straight line at any angle, larger for 2D shapes.
    private static func principalThickness(_ points: [CGPoint]) -> CGFloat {
        let center = UnistrokeGeometry.centroid(points)
        var xx: CGFloat = 0
        var xy: CGFloat = 0
        var yy: CGFloat = 0
        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            xx += dx * dx
            xy += dx * dy
            yy += dy * dy
        }
        let angle = atan2(2 * xy, xx - yy) / 2
        let axis = CGPoint(x: cos(angle), y: sin(angle))
        var along: (min: CGFloat, max: CGFloat) = (
            .greatestFiniteMagnitude,
            -.greatestFiniteMagnitude
        )
        var across = along
        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let a = dx * axis.x + dy * axis.y
            let b = dy * axis.x - dx * axis.y
            along = (min(along.min, a), max(along.max, a))
            across = (min(across.min, b), max(across.max, b))
        }
        let length = along.max - along.min
        guard length > 1e-8 else { return 0 }
        return (across.max - across.min) / length
    }
}

/// Elastic unistroke comparison: banded dynamic time warping over arc length
/// whose local cost is dominated by squared tangent-direction difference, with
/// a light position term. Squaring keeps small wobble cheap while reversed,
/// mirrored, missing or extra structure stays expensive; the warp absorbs the
/// local proportion changes of natural redraws. Both endpoints are anchored.
///
/// A mean alone cannot tell diffuse wobble from one concentrated difference of
/// the same total, such as an extra segment appended to a sharp polyline. The
/// final distance therefore also charges the worst window of the alignment
/// once its average cost exceeds what natural redraws produce.
enum ElasticPathMatcher {
    static let sampleCount = Constants.freePathSampleCount
    /// Coarser resolution for the live HUD, which only needs a yes/no.
    static let liveSampleCount = sampleCount / 2
    static let tangentOffset = 2
    /// Maximum index offset between aligned points (±12.5% of arc length).
    static let warpBand = 8
    static let positionWeight = 0.25
    static let tangentWeight = 2.0
    /// Samples per window (about 15% of arc length) for the concentrated cost.
    static let peakWindow = 10
    static let peakFloor = 0.10
    static let peakWeight = 0.5
    /// `score = exp(-distance / scoreScale)`.
    static let scoreScale = 0.32
    /// Principal-axis thickness over which normalization blends from
    /// aspect-preserving to per-axis scaling.
    static let anisotropicThicknessRange: ClosedRange<CGFloat> = 0.2...0.4

    /// Band and window keep the same share of arc length at any resolution.
    private static func band(for count: Int) -> Int {
        max(1, warpBand * count / sampleCount)
    }

    private static func window(for count: Int) -> Int {
        min(count, max(2, peakWindow * count / sampleCount))
    }

    private enum Step: UInt8 {
        case diagonal
        case horizontal
        case vertical
    }

    static func score(distance: Double) -> Double {
        guard distance.isFinite else { return 0 }
        return min(1, max(0, exp(-distance / scoreScale)))
    }

    /// Largest distance that still scores at least `score`.
    static func maximumDistance(forScore score: Double) -> Double {
        guard score > 0 else { return .infinity }
        return -log(min(1, score)) * scoreScale
    }

    /// Final recognition distance: mean aligned cost plus the concentrated
    /// penalty of the worst window along the chosen alignment.
    static func distance(_ stroke: ElasticPathProfile, _ template: ElasticPathProfile) -> Double {
        guard let (mean, path) = align(stroke, template) else { return .infinity }
        let peak = max(
            worstWindow(of: path, stroke, template, alongStroke: true),
            worstWindow(of: path, stroke, template, alongStroke: false)
        )
        return mean + peakWeight * max(0, peak - peakFloor)
    }

    /// Mean aligned cost only, a lower bound of `distance`. Returns infinity
    /// once every alignment is proven to exceed `abandonAbove`: costs are
    /// non-negative and every alignment crosses every stroke row, so a row
    /// minimum is a valid lower bound. Kept separate from `align` because the
    /// live HUD runs it for every candidate while the stroke is being drawn.
    static func meanDistance(
        _ stroke: ElasticPathProfile,
        _ template: ElasticPathProfile,
        abandonAbove limit: Double = .infinity
    ) -> Double {
        let count = stroke.points.count
        guard count >= 2, template.points.count == count else { return .infinity }
        let band = band(for: count)
        let normalizer = Double(count * 2)
        let abandonTotal = limit.isFinite ? limit * normalizer : .infinity
        // Per column: best cost arriving diagonally, horizontally (template
        // advanced) or vertically (stroke advanced). Forbidding two equal
        // non-diagonal steps in a row bounds the local warp slope to 1/2...2.
        // Rows are band-limited; cells outside a row's band stay infinite.
        var cells = [Double](repeating: .infinity, count: count * 6)
        return cells.withUnsafeMutableBufferPointer { cells in
            var previousDiagonal = cells.baseAddress!
            var previousHorizontal = previousDiagonal + count
            var previousVertical = previousDiagonal + count * 2
            var diagonal = previousDiagonal + count * 3
            var horizontal = previousDiagonal + count * 4
            var vertical = previousDiagonal + count * 5

            for row in 0..<count {
                let lower = max(0, row - band)
                let upper = min(count - 1, row + band)
                if lower > 0 {
                    // Written two rows ago; must not leak into this row's first step.
                    diagonal[lower - 1] = .infinity
                    horizontal[lower - 1] = .infinity
                    vertical[lower - 1] = .infinity
                }
                var rowMinimum = Double.infinity
                for column in lower...upper {
                    let local = localCost(stroke, row, template, column)
                    var arrivedDiagonal = Double.infinity
                    var arrivedHorizontal = Double.infinity
                    var arrivedVertical = Double.infinity
                    if row == 0, column == 0 {
                        arrivedDiagonal = local * 2
                    } else {
                        if row > 0, column > 0 {
                            arrivedDiagonal = min(
                                previousDiagonal[column - 1],
                                previousHorizontal[column - 1],
                                previousVertical[column - 1]
                            ) + local * 2
                        }
                        if column > 0 {
                            arrivedHorizontal = min(diagonal[column - 1], vertical[column - 1])
                                + local
                        }
                        if row > 0 {
                            arrivedVertical = min(
                                previousDiagonal[column],
                                previousHorizontal[column]
                            ) + local
                        }
                    }
                    diagonal[column] = arrivedDiagonal
                    horizontal[column] = arrivedHorizontal
                    vertical[column] = arrivedVertical
                    rowMinimum = min(
                        rowMinimum,
                        arrivedDiagonal,
                        arrivedHorizontal,
                        arrivedVertical
                    )
                }
                if rowMinimum > abandonTotal { return .infinity }
                swap(&previousDiagonal, &diagonal)
                swap(&previousHorizontal, &horizontal)
                swap(&previousVertical, &vertical)
            }
            let last = count - 1
            let total = min(
                previousDiagonal[last],
                previousHorizontal[last],
                previousVertical[last]
            )
            return total.isFinite ? total / normalizer : .infinity
        }
    }

    /// Same recurrence as `meanDistance`, additionally recording each cell's
    /// predecessor so the chosen alignment can be walked back.
    private static func align(
        _ stroke: ElasticPathProfile,
        _ template: ElasticPathProfile
    ) -> (mean: Double, path: [(row: Int, column: Int)])? {
        let count = stroke.points.count
        guard count >= 2, template.points.count == count else { return nil }
        let band = band(for: count)
        let bandWidth = band * 2 + 1
        // Per band cell and arrival step: which step reached the predecessor.
        var origins = [Step](repeating: .diagonal, count: count * bandWidth * 3)
        func originIndex(_ row: Int, _ column: Int, _ step: Step) -> Int {
            (row * bandWidth + column - row + band) * 3 + Int(step.rawValue)
        }

        var cells = [Double](repeating: .infinity, count: count * 6)
        var finalStep = Step.diagonal
        let total: Double? = cells.withUnsafeMutableBufferPointer { cells in
            var previousDiagonal = cells.baseAddress!
            var previousHorizontal = previousDiagonal + count
            var previousVertical = previousDiagonal + count * 2
            var diagonal = previousDiagonal + count * 3
            var horizontal = previousDiagonal + count * 4
            var vertical = previousDiagonal + count * 5

            for row in 0..<count {
                let lower = max(0, row - band)
                let upper = min(count - 1, row + band)
                if lower > 0 {
                    // Written two rows ago; must not leak into this row's first step.
                    diagonal[lower - 1] = .infinity
                    horizontal[lower - 1] = .infinity
                    vertical[lower - 1] = .infinity
                }
                for column in lower...upper {
                    let local = localCost(stroke, row, template, column)
                    var arrivedDiagonal = Double.infinity
                    var arrivedHorizontal = Double.infinity
                    var arrivedVertical = Double.infinity
                    if row == 0, column == 0 {
                        arrivedDiagonal = local * 2
                    } else {
                        if row > 0, column > 0 {
                            let (best, origin) = cheapest(
                                (previousDiagonal[column - 1], .diagonal),
                                (previousHorizontal[column - 1], .horizontal),
                                (previousVertical[column - 1], .vertical)
                            )
                            arrivedDiagonal = best + local * 2
                            origins[originIndex(row, column, .diagonal)] = origin
                        }
                        if column > 0 {
                            let (best, origin) = cheapest(
                                (diagonal[column - 1], .diagonal),
                                (vertical[column - 1], .vertical)
                            )
                            arrivedHorizontal = best + local
                            origins[originIndex(row, column, .horizontal)] = origin
                        }
                        if row > 0 {
                            let (best, origin) = cheapest(
                                (previousDiagonal[column], .diagonal),
                                (previousHorizontal[column], .horizontal)
                            )
                            arrivedVertical = best + local
                            origins[originIndex(row, column, .vertical)] = origin
                        }
                    }
                    diagonal[column] = arrivedDiagonal
                    horizontal[column] = arrivedHorizontal
                    vertical[column] = arrivedVertical
                }
                swap(&previousDiagonal, &diagonal)
                swap(&previousHorizontal, &horizontal)
                swap(&previousVertical, &vertical)
            }

            let last = count - 1
            let (best, step) = cheapest(
                (previousDiagonal[last], .diagonal),
                (previousHorizontal[last], .horizontal),
                (previousVertical[last], .vertical)
            )
            finalStep = step
            return best.isFinite ? best : nil
        }
        guard let total else { return nil }

        var path: [(row: Int, column: Int)] = []
        path.reserveCapacity(count * 2)
        var row = count - 1
        var column = count - 1
        var step = finalStep
        while true {
            path.append((row, column))
            if row == 0, column == 0 { break }
            let origin = origins[originIndex(row, column, step)]
            switch step {
            case .diagonal:
                row -= 1
                column -= 1
            case .horizontal:
                column -= 1
            case .vertical:
                row -= 1
            }
            step = origin
        }
        return (total / Double(count * 2), path)
    }

    /// Worst average local cost over a window of consecutive samples on one
    /// side, each sample averaging the cells it is aligned to.
    private static func worstWindow(
        of path: [(row: Int, column: Int)],
        _ stroke: ElasticPathProfile,
        _ template: ElasticPathProfile,
        alongStroke: Bool
    ) -> Double {
        let count = stroke.points.count
        var sums = [Double](repeating: 0, count: count)
        var hits = [Double](repeating: 0, count: count)
        for (row, column) in path {
            let index = alongStroke ? row : column
            sums[index] += localCost(stroke, row, template, column)
            hits[index] += 1
        }
        let averages = zip(sums, hits).map { $1 > 0 ? $0 / $1 : 0 }
        let window = window(for: count)
        var running = averages.prefix(window).reduce(0, +)
        var worst = running
        for index in window..<count {
            running += averages[index] - averages[index - window]
            worst = max(worst, running)
        }
        return worst / Double(window)
    }

    /// Earlier candidates win ties, so diagonal steps are preferred.
    @inline(__always)
    private static func cheapest(
        _ first: (Double, Step),
        _ second: (Double, Step)
    ) -> (Double, Step) {
        second.0 < first.0 ? second : first
    }

    @inline(__always)
    private static func cheapest(
        _ first: (Double, Step),
        _ second: (Double, Step),
        _ third: (Double, Step)
    ) -> (Double, Step) {
        cheapest(cheapest(first, second), third)
    }

    @inline(__always)
    private static func localCost(
        _ stroke: ElasticPathProfile,
        _ row: Int,
        _ template: ElasticPathProfile,
        _ column: Int
    ) -> Double {
        let a = stroke.points[row]
        let b = template.points[column]
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        var turn = abs(stroke.headings[row] - template.headings[column])
        if turn > .pi { turn = 2 * .pi - turn }
        let normalizedTurn = turn / .pi
        return (dx * dx + dy * dy).squareRoot() * positionWeight
            + normalizedTurn * normalizedTurn * tangentWeight
    }
}
