import AppKit

/// Small utility for numeric widths and frame math used by the window state handling.
enum WindowGeometry {
    static func frame(
        size: CGSize,
        on screen: NSScreen,
        margin: CGFloat = 20
    ) -> CGRect {
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        )
        return CGRect(origin: origin, size: size)
    }

    static func isVisible(_ frame: CGRect, on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        let intersection = visible.intersection(frame)
        guard !intersection.isNull else { return false }
        let area = intersection.width * intersection.height
        let total = max(frame.width * frame.height, 1)
        return area / total >= 0.35
    }

    /// Ensures the window keeps its size and stays inside a screen's visible frame.
    static func clamped(_ frame: CGRect, to screen: NSScreen, minSize: CGSize) -> CGRect {
        let visible = screen.visibleFrame
        var result = frame
        result.size.width = max(min(frame.width, visible.width), minSize.width)
        result.size.height = max(min(frame.height, visible.height), minSize.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }
}
