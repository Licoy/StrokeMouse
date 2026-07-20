import ApplicationServices
import Foundation

struct GestureTargetAXAttribute {
    let name: CFString
    let operation: GestureTargetAXOperation
}

@MainActor
enum GestureTargetAXAccessor {
    static func copyElement(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> AXUIElement {
        let value = try copyValue(from: element, attribute: attribute)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return value as! AXUIElement
    }

    static func copyString(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> String {
        let value = try copyValue(from: element, attribute: attribute)
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return value as! String
    }

    static func copyPoint(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> CGPoint {
        let axValue = try copyAXValue(
            from: element,
            attribute: attribute,
            expectedType: .cgPoint
        )
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return point
    }

    static func copySize(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> CGSize {
        let axValue = try copyAXValue(
            from: element,
            attribute: attribute,
            expectedType: .cgSize
        )
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return size
    }

    private static func copyAXValue(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute,
        expectedType: AXValueType
    ) throws -> AXValue {
        let value = try copyValue(from: element, attribute: attribute)
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == expectedType else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return axValue
    }

    private static func copyValue(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute.name, &value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: attribute.operation,
                code: result
            )
        }
        guard let value else {
            throw GestureTargetError.unexpectedAXValue(operation: attribute.operation)
        }
        return value
    }
}
