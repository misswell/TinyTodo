import AppKit
import Foundation
import os

/// Observes system lifecycle events that change what the panel should show.
@MainActor
final class AppLifecycle {
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "lifecycle")
    private let onWake: () -> Void

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.logger.info("system woke up")
                self?.onWake()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onWake()
            }
        })
    }

}
