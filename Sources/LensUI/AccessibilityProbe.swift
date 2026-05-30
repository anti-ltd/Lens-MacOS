import AppKit
import ApplicationServices

/// Best-effort "where is typing happening" probe via Accessibility: the caret
/// rectangle of the focused text element, falling back to the element's frame
/// centre. Returns a point in global top-left points (AX's coordinate space),
/// matching the rest of the event track. Needs Accessibility trust (already
/// required for the global hotkeys).
@MainActor
enum AccessibilityProbe {
    static func typingFocus() -> CGPoint? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        // 1. Caret: bounds for the current selection/insertion range.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
               let boundsRef {
                var rect = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width.isFinite, rect.height.isFinite {
                    return CGPoint(x: rect.midX, y: rect.midY)
                }
            }
        }

        // 2. Fallback: the focused element's frame centre.
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let posRef, let sizeRef {
            var pos = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(posRef as! AXValue, .cgPoint, &pos), AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
                return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
            }
        }
        return nil
    }
}
