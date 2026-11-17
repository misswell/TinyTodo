import AppKit
import SwiftUI

/// Rounded `NSVisualEffectView` background. `NSVisualEffectView` ignores SwiftUI's
/// `clipShape`, so the rounding is done with a mask image instead.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 11

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    }

    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let size = NSSize(width: edge, height: edge)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()
        image.unlockFocus()
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
