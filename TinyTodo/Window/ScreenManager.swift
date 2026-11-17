import AppKit

/// Keeps the panel on a valid display when monitors are connected/disconnected or the
/// resolution changes. Never hides the panel, only repositions/clamps it.
@MainActor
final class ScreenManager {
    private let windowState: WindowStateManager
    private weak var panel: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var onChange: (() -> Void)?

    init(windowState: WindowStateManager) {
        self.windowState = windowState
    }

    func attach(to panel: NSWindow, onScreenChange: @escaping () -> Void) {
        self.panel = panel
        self.onChange = onScreenChange
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didChangeScreenParametersNotification,
            NSWorkspace.didWakeNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleScreenChange()
                }
            })
        }
    }


    func handleScreenChange() {
        guard let panel else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let currentScreen = panel.screen
        if let currentScreen, WindowGeometry.isVisible(panel.frame, on: currentScreen) {
            windowState.saveFrame(panel.frame, on: currentScreen)
            return
        }

        // The display the window was on is gone: fall back to the main screen, preferring a frame
        // we saved for that screen, otherwise anchor to its top-right corner.
        guard let target = TestScreenPolicy.preferredScreen ?? NSScreen.main ?? screens.first else { return }
        let restored = windowState.restoreFrame(on: target)
        let size = CGSize(
            width: max(panel.frame.width, AppInfo.minimumPanelSize.width),
            height: max(panel.frame.height, AppInfo.minimumPanelSize.height)
        )
        let base = restored ?? WindowGeometry.frame(size: size, on: target)
        let frame = WindowGeometry.clamped(base, to: target, minSize: AppInfo.minimumPanelSize)
        panel.setFrame(frame, display: true)
        windowState.saveFrame(frame, on: target)
        onChange?()
    }
}
