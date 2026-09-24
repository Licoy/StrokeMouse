import CoreGraphics
import Foundation

enum ScrollInputDevice: Equatable, Sendable {
    case lineWheel
    case preciseWheel
    case gestureSurface
}

struct ScrollEventSample: Equatable, Sendable {
    var isContinuous: Bool
    var scrollPhase: Int64
    var momentumPhase: Int64
    /// Momentum-option phase (field 173). It is not a delta and must not be negated.
    var momentumOptionPhase: Int64
    var lineDeltaY: Int64
    var lineDeltaX: Int64
    var fixedDeltaY: Double
    var fixedDeltaX: Double
    var pointDeltaY: Int64
    var pointDeltaX: Int64
    var acceleratedDeltaY: Int64
    var acceleratedDeltaX: Int64
    var rawDeltaY: Int64
    var rawDeltaX: Int64
    var flags: CGEventFlags

    init(
        isContinuous: Bool = false,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        momentumOptionPhase: Int64 = 0,
        lineDeltaY: Int64 = 0,
        lineDeltaX: Int64 = 0,
        fixedDeltaY: Double = 0,
        fixedDeltaX: Double = 0,
        pointDeltaY: Int64 = 0,
        pointDeltaX: Int64 = 0,
        acceleratedDeltaY: Int64 = 0,
        acceleratedDeltaX: Int64 = 0,
        rawDeltaY: Int64 = 0,
        rawDeltaX: Int64 = 0,
        flags: CGEventFlags = []
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.momentumOptionPhase = momentumOptionPhase
        self.lineDeltaY = lineDeltaY
        self.lineDeltaX = lineDeltaX
        self.fixedDeltaY = fixedDeltaY
        self.fixedDeltaX = fixedDeltaX
        self.pointDeltaY = pointDeltaY
        self.pointDeltaX = pointDeltaX
        self.acceleratedDeltaY = acceleratedDeltaY
        self.acceleratedDeltaX = acceleratedDeltaX
        self.rawDeltaY = rawDeltaY
        self.rawDeltaX = rawDeltaX
        self.flags = flags
    }

    init(event: CGEvent) {
        isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        momentumOptionPhase = event.getIntegerValueField(
            .scrollWheelEventMomentumOptionPhase
        )
        lineDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        lineDeltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        pointDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        pointDeltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        acceleratedDeltaY = event.getIntegerValueField(
            .scrollWheelEventAcceleratedDeltaAxis1
        )
        acceleratedDeltaX = event.getIntegerValueField(
            .scrollWheelEventAcceleratedDeltaAxis2
        )
        rawDeltaY = event.getIntegerValueField(.scrollWheelEventRawDeltaAxis1)
        rawDeltaX = event.getIntegerValueField(.scrollWheelEventRawDeltaAxis2)
        flags = event.flags
    }

    var isZeroDelta: Bool {
        lineDeltaY == 0 && lineDeltaX == 0
            && fixedDeltaY == 0 && fixedDeltaX == 0
            && pointDeltaY == 0 && pointDeltaX == 0
            && acceleratedDeltaY == 0 && acceleratedDeltaX == 0
            && rawDeltaY == 0 && rawDeltaX == 0
    }
}

/// Hot-path copy. Bools and doubles only — no sets or strings.
struct ScrollTapSnapshot: Equatable, Sendable {
    var enhancementEnabled = false
    var frontmostExcluded = false
    var reverseMouseVertical = false
    var reverseMouseHorizontal = false
    var reverseTrackpadVertical = false
    var reverseTrackpadHorizontal = false
    var smoothEnabled = false
    var smoothStepPixels = ScrollSmoothPreset.standardStep
    var smoothDurationMs = ScrollSmoothPreset.standardDurationMs
    var smoothAcceleration = ScrollSmoothPreset.standardAcceleration

    var smoothParameters: ScrollSmoothParameters {
        ScrollSmoothParameters(
            stepPixels: smoothStepPixels,
            durationMs: smoothDurationMs,
            acceleration: smoothAcceleration
        )
    }

    init() {}

    init(
        configuration: ScrollEnhancementConfiguration,
        frontmostExcluded: Bool
    ) {
        let parameters = configuration.effectiveSmoothParameters
        enhancementEnabled = configuration.isEnabled
        self.frontmostExcluded = frontmostExcluded
        reverseMouseVertical = configuration.reverseMouseVertical
        reverseMouseHorizontal = configuration.reverseMouseHorizontal
        reverseTrackpadVertical = configuration.reverseTrackpadVertical
        reverseTrackpadHorizontal = configuration.reverseTrackpadHorizontal
        smoothEnabled = configuration.smoothEnabled
        smoothStepPixels = parameters.stepPixels
        smoothDurationMs = parameters.durationMs
        smoothAcceleration = parameters.acceleration
    }
}

enum ScrollDecision: Equatable, Sendable {
    case passThrough(cancelsAnimation: Bool)
    case reverse(vertical: Bool, horizontal: Bool, cancelsAnimation: Bool)
    case smooth(directionY: Int, directionX: Int)
}

enum ScrollEventClassifier {
    private static let smoothBypassModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    static func device(for sample: ScrollEventSample) -> ScrollInputDevice {
        guard sample.isContinuous else { return .lineWheel }
        if sample.scrollPhase != 0
            || sample.momentumPhase != 0
            || sample.momentumOptionPhase != 0
        {
            return .gestureSurface
        }
        return .preciseWheel
    }

    static func decide(
        _ sample: ScrollEventSample,
        snapshot: ScrollTapSnapshot
    ) -> ScrollDecision {
        if sample.isZeroDelta {
            return .passThrough(cancelsAnimation: false)
        }
        let bypassesSmooth = !sample.flags.intersection(smoothBypassModifiers).isEmpty
        if !snapshot.enhancementEnabled || snapshot.frontmostExcluded {
            return .passThrough(cancelsAnimation: true)
        }

        let device = device(for: sample)
        let axes = reverseAxes(for: device, sample: sample, snapshot: snapshot)
        if device == .lineWheel && snapshot.smoothEnabled && !bypassesSmooth {
            let directionY = axisDirection(sample, vertical: true) * (axes.vertical ? -1 : 1)
            let directionX = axisDirection(sample, vertical: false) * (axes.horizontal ? -1 : 1)
            if directionY == 0 && directionX == 0 {
                return .passThrough(cancelsAnimation: false)
            }
            return .smooth(directionY: directionY, directionX: directionX)
        }
        if axes.vertical || axes.horizontal {
            return .reverse(
                vertical: axes.vertical,
                horizontal: axes.horizontal,
                cancelsAnimation: bypassesSmooth
            )
        }
        return .passThrough(cancelsAnimation: bypassesSmooth)
    }

    /// Precise wheels are mice without a gesture phase, so they share the mouse
    /// toggles. Shift turns a vertical notch into horizontal scrolling, so that
    /// axis follows the vertical toggle.
    private static func reverseAxes(
        for device: ScrollInputDevice,
        sample: ScrollEventSample,
        snapshot: ScrollTapSnapshot
    ) -> (vertical: Bool, horizontal: Bool) {
        switch device {
        case .gestureSurface:
            return (
                snapshot.reverseTrackpadVertical,
                snapshot.reverseTrackpadHorizontal
            )
        case .lineWheel, .preciseWheel:
            let vertical = snapshot.reverseMouseVertical
            let horizontal = sample.flags.contains(.maskShift)
                ? vertical
                : snapshot.reverseMouseHorizontal
            return (vertical, horizontal)
        }
    }

    private static func axisDirection(
        _ sample: ScrollEventSample,
        vertical: Bool
    ) -> Int {
        let line = vertical ? sample.lineDeltaY : sample.lineDeltaX
        if line != 0 { return line > 0 ? 1 : -1 }
        let fixed = vertical ? sample.fixedDeltaY : sample.fixedDeltaX
        if fixed != 0 { return fixed > 0 ? 1 : -1 }
        let point = vertical ? sample.pointDeltaY : sample.pointDeltaX
        if point != 0 { return point > 0 ? 1 : -1 }
        let accelerated = vertical
            ? sample.acceleratedDeltaY
            : sample.acceleratedDeltaX
        if accelerated != 0 { return accelerated > 0 ? 1 : -1 }
        let raw = vertical ? sample.rawDeltaY : sample.rawDeltaX
        if raw != 0 { return raw > 0 ? 1 : -1 }
        return 0
    }
}

enum ScrollEventMutator {
    /// Negate line, then fixed, then point, then the accelerated / raw deltas.
    /// Field 173 is a phase and is left untouched. Later writes win if setting
    /// an earlier field makes WindowServer rewrite a later one.
    static func reverse(
        _ event: CGEvent,
        vertical: Bool,
        horizontal: Bool
    ) {
        // Snapshot first. Writing the line delta makes WindowServer rewrite the
        // fixed and point fields, so a later read would negate the rewritten
        // value instead of the original.
        if vertical {
            writeNegated(
                event,
                line: .scrollWheelEventDeltaAxis1,
                fixed: .scrollWheelEventFixedPtDeltaAxis1,
                point: .scrollWheelEventPointDeltaAxis1,
                accelerated: .scrollWheelEventAcceleratedDeltaAxis1,
                raw: .scrollWheelEventRawDeltaAxis1
            )
        }
        if horizontal {
            writeNegated(
                event,
                line: .scrollWheelEventDeltaAxis2,
                fixed: .scrollWheelEventFixedPtDeltaAxis2,
                point: .scrollWheelEventPointDeltaAxis2,
                accelerated: .scrollWheelEventAcceleratedDeltaAxis2,
                raw: .scrollWheelEventRawDeltaAxis2
            )
        }
    }

    private static func writeNegated(
        _ event: CGEvent,
        line: CGEventField,
        fixed: CGEventField,
        point: CGEventField,
        accelerated: CGEventField,
        raw: CGEventField
    ) {
        let lineValue = event.getIntegerValueField(line)
        let fixedValue = event.getDoubleValueField(fixed)
        let pointValue = event.getIntegerValueField(point)
        let acceleratedValue = event.getIntegerValueField(accelerated)
        let rawValue = event.getIntegerValueField(raw)
        if lineValue != 0, lineValue != Int64.min {
            event.setIntegerValueField(line, value: -lineValue)
        }
        if fixedValue != 0, fixedValue.isFinite {
            event.setDoubleValueField(fixed, value: -fixedValue)
        }
        if pointValue != 0, pointValue != Int64.min {
            event.setIntegerValueField(point, value: -pointValue)
        }
        if acceleratedValue != 0, acceleratedValue != Int64.min {
            event.setIntegerValueField(accelerated, value: -acceleratedValue)
        }
        if rawValue != 0, rawValue != Int64.min {
            event.setIntegerValueField(raw, value: -rawValue)
        }
    }
}
