import Foundation

/// Carries the quick-input growth to the AppKit layer.
///
/// SwiftUI cannot resize the `NSPanel` it lives in, and a `List` refuses to shrink, so the bar
/// growing by N points would otherwise push the tab bar out of the window.
enum QuickInputHeightRelay {
    static let notification = Notification.Name("app.tinytodo.quickInputHeightChanged")
    static let deltaKey = "delta"

    static func post(delta: CGFloat) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: [deltaKey: delta])
    }
}
