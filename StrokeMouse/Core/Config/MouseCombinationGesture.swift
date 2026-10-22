import CoreGraphics
import Foundation

enum MouseWheelDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case up, down
    var id: String { rawValue }
    var displayKey: String { "combination.wheel.\(rawValue)" }
}

enum MouseCombinationAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case rightClick, leftClick, wheelUp, wheelDown
    var id: String { rawValue }
    var displayKey: String { "combination.action.\(rawValue)" }
    var wheelDirection: MouseWheelDirection? {
        switch self {
        case .wheelUp: return .up
        case .wheelDown: return .down
        default: return nil
        }
    }
}

enum MouseScreenEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, bottom, left, right
    var id: String { rawValue }
    var displayKey: String { "combination.edge.\(rawValue)" }

    /// Quartz display bounds, including displays above/left of the main display.
    /// Shared display seams count as edges of each physical display.
    func contains(_ point: CGPoint, in displays: [CGRect], tolerance: CGFloat = 3) -> Bool {
        displays.contains { frame in
            guard point.x >= frame.minX, point.x <= frame.maxX,
                  point.y >= frame.minY, point.y <= frame.maxY else { return false }
            switch self {
            case .top: return abs(point.y - frame.minY) <= tolerance
            case .bottom: return abs(point.y - frame.maxY) <= tolerance
            case .left: return abs(point.x - frame.minX) <= tolerance
            case .right: return abs(point.x - frame.maxX) <= tolerance
            }
        }
    }
}

struct MouseCombinationGesture: Codable, Equatable, Hashable, Sendable {
    /// nil means hold right, then scroll or click left; an edge needs no held button.
    var edge: MouseScreenEdge?
    var action: MouseCombinationAction

    init(edge: MouseScreenEdge? = nil, action: MouseCombinationAction = .wheelUp) {
        self.edge = edge
        self.action = action
    }

    var isValid: Bool { edge == nil ? action != .rightClick : action != .leftClick }
    var needsHeldRight: Bool { edge == nil }

    func accepts(location: CGPoint, displays: [CGRect]) -> Bool {
        isValid && (edge?.contains(location, in: displays) ?? true)
    }

    /// Held combinations and an edge right click reserve a right press here;
    /// edge wheels are admitted by the wheel alone.
    func acceptsRightPress(at location: CGPoint, displays: [CGRect]) -> Bool {
        (needsHeldRight || action == .rightClick)
            && accepts(location: location, displays: displays)
    }
}

/// Smooth scrolling delivers many frames for a single wheel movement. Consume
/// those frames, but rate-limit actions so one notch cannot switch dozens of tabs.
/// A fresh hold and an immediate direction reversal remain responsive.
struct MouseCombinationWheelRepeatGate {
    private var lastAction: MouseCombinationAction?
    private var lastTimestamp: TimeInterval?
    static let interval: TimeInterval = 0.12
    private let minimumInterval: TimeInterval

    init(interval: TimeInterval = Self.interval) {
        minimumInterval = interval
    }

    mutating func shouldExecute(action: MouseCombinationAction, preciseTimestamp: TimeInterval?) -> Bool {
        guard let timestamp = preciseTimestamp else {
            lastAction = nil
            lastTimestamp = nil
            return true
        }
        if lastAction == action, let previous = lastTimestamp,
           timestamp >= previous, timestamp - previous < minimumInterval {
            return false
        }
        lastAction = action
        lastTimestamp = timestamp
        return true
    }
}
