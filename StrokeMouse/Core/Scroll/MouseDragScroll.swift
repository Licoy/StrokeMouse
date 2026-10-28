import CoreGraphics
import Foundation

struct MouseDragScrollConfiguration: Codable, Equatable, Hashable, Sendable {
    var sensitivity: Double = 1
    var reversesDirection: Bool = false
    static let sensitivityRange = 0.25...4.0
    var isValid: Bool { sensitivity.isFinite && Self.sensitivityRange.contains(sensitivity) }

    init(sensitivity: Double = 1, reversesDirection: Bool = false) {
        self.sensitivity = sensitivity
        self.reversesDirection = reversesDirection
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try values.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1
        reversesDirection = try values.decodeIfPresent(Bool.self, forKey: .reversesDirection) ?? false
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .sensitivity, in: values,
                debugDescription: "Drag scroll sensitivity must be finite and within 0.25...4")
        }
    }
}

/// AppKit y points up, while positive CG y scrolls toward the document top
/// (content down); negate y so content follows the pointer, and preserve x.
struct MouseDragScrollSession {
    struct Frame: Equatable {
        let x: Int32
        let y: Int32
        let phase: Int64
    }
    let origin: CGPoint
    let configuration: MouseDragScrollConfiguration
    private(set) var isActive = false
    private var previous: CGPoint
    private var remainder = CGPoint.zero
    /// Separates a slightly shaky right click (replayed) from a drag. Fixed
    /// rather than `minStrokeDistance` so scrolling still starts promptly.
    static let deadzone: CGFloat = 10

    init(origin: CGPoint, configuration: MouseDragScrollConfiguration) {
        self.origin = origin
        self.previous = origin
        self.configuration = configuration
    }

    mutating func sample(_ point: CGPoint) -> Frame? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        var phase: Int64 = 2
        if !isActive {
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            let distance = hypot(dx, dy)
            guard distance >= Self.deadzone else { return nil }
            isActive = true
            phase = 1
            // Discard only the fixed deadzone, preserving fast first movement.
            previous = CGPoint(x: origin.x + dx * Self.deadzone / distance,
                               y: origin.y + dy * Self.deadzone / distance)
        }
        let scale = configuration.sensitivity * (configuration.reversesDirection ? -1 : 1)
        remainder.x += (point.x - previous.x) * scale
        remainder.y -= (point.y - previous.y) * scale
        previous = point
        let x = Int32(remainder.x.clampedToInt32)
        let y = Int32(remainder.y.clampedToInt32)
        remainder.x -= CGFloat(x)
        remainder.y -= CGFloat(y)
        guard phase == 1 || x != 0 || y != 0 else { return nil }
        return Frame(x: x, y: y, phase: phase)
    }

    mutating func finish(cancelled: Bool) -> Frame? {
        guard isActive else { return nil }
        isActive = false
        remainder = .zero
        return Frame(x: 0, y: 0, phase: cancelled ? 8 : 4)
    }
}

private extension CGFloat {
    var clampedToInt32: CGFloat { Swift.min(CGFloat(Int32.max), Swift.max(CGFloat(Int32.min), self)).rounded(.towardZero) }
}

/// Movement has one owner within the most specific applicable scope tier.
enum MouseDragScrollSelection {
    case drawn
    case drag(TargetedGesture)
    case conflict([UUID])

    static func select(_ targeted: [TargetedGesture]) -> Self {
        let movement = targeted.filter {
            switch $0.profile.input {
            case .drawn: return true
            case .mouseCombination(let combo): return combo.action == .dragScroll
            default: return false
            }
        }
        guard let tier = movement.map({ GestureScopeTier($0.profile.scope) }).min() else { return .drawn }
        let preferred = movement.filter { GestureScopeTier($0.profile.scope) == tier }
        let drags = preferred.filter {
            if case .mouseCombination(let combo) = $0.profile.input { return combo.action == .dragScroll }
            return false
        }
        guard !drags.isEmpty else { return .drawn }
        return preferred.count == 1 ? .drag(drags[0]) : .conflict(preferred.map(\.profile.id))
    }
}
