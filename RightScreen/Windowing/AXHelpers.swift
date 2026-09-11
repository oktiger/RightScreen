import ApplicationServices
import CoreGraphics

enum AXHelpers {
    static func attribute(_ attribute: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ attributeName: CFString, of element: AXUIElement) -> String? {
        attribute(attributeName, of: element) as? String
    }

    static func bool(_ attributeName: CFString, of element: AXUIElement) -> Bool? {
        attribute(attributeName, of: element) as? Bool
    }

    static func windows(of application: AXUIElement) -> [AXUIElement] {
        attribute(kAXWindowsAttribute as CFString, of: application) as? [AXUIElement] ?? []
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] ?? []
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let positionValue = attribute(kAXPositionAttribute as CFString, of: element),
            let sizeValue = attribute(kAXSizeAttribute as CFString, of: element),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func isSettable(_ attribute: CFString, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success
            && settable.boolValue
    }

    static func set(point: CGPoint, attribute: CFString, on element: AXUIElement) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element, attribute, value)
    }

    static func set(size: CGSize, attribute: CFString, on element: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(element, attribute, value)
    }
}
