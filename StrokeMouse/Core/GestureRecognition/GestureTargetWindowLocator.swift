import ApplicationServices
import Foundation

struct GestureTargetWindowDescriptor: Equatable, Sendable {
    let windowNumber: CGWindowID
    let processIdentifier: pid_t
    let layer: Int
    let bounds: CGRect

    init(
        windowNumber: CGWindowID = kCGNullWindowID,
        processIdentifier: pid_t,
        layer: Int = 0,
        bounds: CGRect
    ) {
        self.windowNumber = windowNumber
        self.processIdentifier = processIdentifier
        self.layer = layer
        self.bounds = bounds.standardized
    }
}

struct GestureTargetVisibleWindow: Equatable, Sendable {
    let descriptor: GestureTargetWindowDescriptor
    let alpha: CGFloat
    let ownerBundleIdentifier: String?
}

enum GestureTargetWindowLocator {
    static func parse(
        _ records: [[String: Any]],
        bundleIdentifier: (pid_t) -> String?
    ) throws -> [GestureTargetVisibleWindow] {
        try records.map { record in
            guard let windowNumber: CGWindowID = integer(record, key: kCGWindowNumber),
                  windowNumber != kCGNullWindowID,
                  let processIdentifier: pid_t = integer(record, key: kCGWindowOwnerPID),
                  processIdentifier > 0,
                  let layer: Int = integer(record, key: kCGWindowLayer),
                  let alpha = decimal(record, key: kCGWindowAlpha),
                  alpha.isFinite,
                  let boundsDictionary = record[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  isValid(bounds)
            else {
                throw GestureTargetError.unexpectedCaptureFailure("Invalid CG window record")
            }
            return GestureTargetVisibleWindow(
                descriptor: GestureTargetWindowDescriptor(
                    windowNumber: windowNumber,
                    processIdentifier: processIdentifier,
                    layer: layer,
                    bounds: bounds
                ),
                alpha: alpha,
                ownerBundleIdentifier: bundleIdentifier(processIdentifier)
            )
        }
    }

    static func locate(
        at point: CGPoint,
        windows: [GestureTargetVisibleWindow],
        displayBounds: [CGRect],
        dockWindowLevel: Int,
        dockCarrierDoesNotHit: (GestureTargetVisibleWindow) throws -> Bool
    ) throws -> GestureTargetWindowDescriptor {
        for window in windows where window.descriptor.bounds.contains(point) {
            if window.descriptor.layer == 0 {
                return window.descriptor
            }
            guard window.ownerBundleIdentifier == "com.apple.dock",
                  window.descriptor.layer == dockWindowLevel,
                  displayBounds.contains(window.descriptor.bounds),
                  try dockCarrierDoesNotHit(window)
            else {
                throw GestureTargetError.windowUnavailable
            }
        }
        throw GestureTargetError.noElementAtPointer
    }

    private static func integer<T: BinaryInteger>(
        _ record: [String: Any],
        key: CFString
    ) -> T? {
        guard let value = record[key as String] as? NSNumber else { return nil }
        let decimal = value.doubleValue
        guard decimal.isFinite, decimal.rounded() == decimal else { return nil }
        return T(exactly: decimal)
    }

    private static func decimal(
        _ record: [String: Any],
        key: CFString
    ) -> CGFloat? {
        guard let value = record[key as String] as? NSNumber else { return nil }
        return CGFloat(value.doubleValue)
    }

    private static func isValid(_ bounds: CGRect) -> Bool {
        let values = [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height]
        return values.allSatisfy(\.isFinite) && bounds.width >= 0 && bounds.height >= 0
    }
}
