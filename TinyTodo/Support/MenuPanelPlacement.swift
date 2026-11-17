import CoreGraphics

/// Positions the panel like a menu-bar app's own dropdown: centred under the status item,
/// just below the menu bar, clamped to the visible frame of that display.
enum MenuPanelPlacement {
    static func frame(
        buttonScreenFrame: CGRect,
        visibleFrame: CGRect,
        size: CGSize,
        gap: CGFloat = 6
    ) -> CGRect {
        let width = min(max(size.width, 1), visibleFrame.width)
        let height = min(max(size.height, 1), visibleFrame.height)
        var x = buttonScreenFrame.midX - width / 2
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - width)
        var y = buttonScreenFrame.minY - height - gap
        if y < visibleFrame.minY { y = visibleFrame.minY }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
