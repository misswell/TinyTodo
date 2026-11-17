import AppKit
import SwiftUI

/// A real AppKit floating panel. SwiftUI only draws the content; the window behavior
/// (level, Spaces, full-screen auxiliary, frame persistence) stays in AppKit.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let router: AppRouter
    private let todo: TodoViewModel
    private let history: HistoryViewModel
    private let windowState: WindowStateManager
    private let screenManager: ScreenManager
    private let panel: FloatingPanel

    var onOpenSettings: (() -> Void)?

    private enum PresentationMode {
        case floating
        case menu
    }

    private var presentationMode: PresentationMode = .floating
    private var menuClickMonitor: Any?
    private var menuResignObserver: NSObjectProtocol?

    init(
        settings: SettingsStore,
        router: AppRouter,
        todo: TodoViewModel,
        history: HistoryViewModel,
        windowState: WindowStateManager
    ) {
        self.settings = settings
        self.router = router
        self.todo = todo
        self.history = history
        self.windowState = windowState
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable, .closable]
        if !AppInfo.isRunningUITests {
            // UI automation needs a regular key window to synthesize keyboard events.
            styleMask.insert(.nonactivatingPanel)
        }
        self.panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: AppInfo.defaultPanelSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        self.screenManager = ScreenManager(windowState: windowState)
        super.init()
        configurePanel()
        installContent()
        applySettings()
        positionDefault()
        screenManager.attach(to: panel) { [weak self] in
            self?.saveCurrentFrame()
        }
    }

    // MARK: - Public API

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }
    var window: NSWindow { panel }

    /// Menu-bar click: expand the panel as the app's own dropdown, anchored under the status item.
    func toggleFromMenuBar(anchor: NSStatusBarButton?) {
        if panel.isVisible, panel.isKeyWindow {
            hide()
        } else {
            showAsMenu(anchor: anchor)
        }
    }

    private func showAsMenu(anchor: NSStatusBarButton?) {
        guard let anchor, let buttonWindow = anchor.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            show()
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = CGSize(
            width: max(panel.frame.width, AppInfo.minimumPanelSize.width),
            height: max(panel.frame.height, AppInfo.minimumPanelSize.height)
        )
        let frame = MenuPanelPlacement.frame(
            buttonScreenFrame: buttonFrame,
            visibleFrame: screen.visibleFrame,
            size: size
        )
        panel.setFrame(frame, display: false)
        presentationMode = .menu
        installMenuDismissMonitors()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        switch router.tab {
        case .todo:
            router.requestInputFocus()
        case .history:
            router.requestSearchFocus()
        }
        Task {
            await todo.refreshStats()
            if router.tab == .history {
                history.scheduleReload(debounce: false)
            }
        }
    }

    func show(tab: AppRouter.Tab? = nil, focusInput: Bool = true) {
        removeMenuDismissMonitors()
        presentationMode = .floating
        if let tab {
            router.tab = tab
        }
        ensureFrameIsUsable()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        if focusInput {
            switch router.tab {
            case .todo:
                router.requestInputFocus()
            case .history:
                router.requestSearchFocus()
            }
        }

        // Login-launched accessory apps are not always allowed to activate on first try.
        if !NSApp.isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.panel.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKey()
            }
        }
        Task {
            await todo.refreshStats()
            if router.tab == .history {
                history.scheduleReload(debounce: false)
            }
        }
    }

    func hide() {
        if presentationMode == .floating {
            saveCurrentFrame()
        }
        removeMenuDismissMonitors()
        presentationMode = .floating
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible, panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func showHistory() {
        show(tab: .history, focusInput: false)
    }

    func focusInput() {
        show(tab: .todo, focusInput: true)
    }

    func resetPosition() {
        windowState.reset()
        positionDefault()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func saveCurrentFrame() {
        guard presentationMode == .floating else { return }
        guard panel.frame.width > 0, panel.frame.height > 0 else { return }
        if let screen = panel.screen ?? NSScreen.main {
            windowState.saveFrame(panel.frame, on: screen)
        }
    }

    func applySettings() {
        panel.level = settings.alwaysOnTop ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle]
        if settings.acrossSpaces {
            behavior.insert(.canJoinAllSpaces)
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior
        panel.alphaValue = settings.opacity
    }

    // MARK: - Menu presentation

    private func installMenuDismissMonitors() {
        removeMenuDismissMonitors()
        menuClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel {
                self.hide()
            }
            return event
        }
        menuResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
    }

    private func removeMenuDismissMonitors() {
        if let menuClickMonitor {
            NSEvent.removeMonitor(menuClickMonitor)
            self.menuClickMonitor = nil
        }
        if let menuResignObserver {
            NotificationCenter.default.removeObserver(menuResignObserver)
            self.menuResignObserver = nil
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.title = AppInfo.displayName
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = AppInfo.minimumPanelSize
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
    }

    private func installContent() {
        let root = PanelRootView(
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onHide: { [weak self] in self?.hide() }
        )
        .environment(settings)
        .environment(router)
        .environment(todo)
        .environment(history)

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 11
        panel.contentView?.layer?.masksToBounds = true
    }

    private func positionDefault() {
        guard let screen = TestScreenPolicy.preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = AppInfo.defaultPanelSize
        let restored = windowState.restoreFrame(on: screen)
        let proposed = restored ?? WindowGeometry.frame(size: size, on: screen)
        let frame = WindowGeometry.clamped(proposed, to: screen, minSize: AppInfo.minimumPanelSize)
        panel.setFrame(frame, display: false)
        windowState.saveFrame(frame, on: screen)
    }

    private func ensureFrameIsUsable() {
        guard panel.frame.width >= AppInfo.minimumPanelSize.width,
              panel.frame.height >= AppInfo.minimumPanelSize.height,
              let screen = panel.screen ?? TestScreenPolicy.preferredScreen ?? NSScreen.main
        else {
            positionDefault()
            return
        }
        if WindowGeometry.isVisible(panel.frame, on: screen) {
            return
        }
        let size = CGSize(
            width: max(panel.frame.width, AppInfo.minimumPanelSize.width),
            height: max(panel.frame.height, AppInfo.minimumPanelSize.height)
        )
        let frame = WindowGeometry.clamped(
            windowState.restoreFrame(on: screen) ?? WindowGeometry.frame(size: size, on: screen),
            to: screen,
            minSize: AppInfo.minimumPanelSize
        )
        panel.setFrame(frame, display: false)
        windowState.saveFrame(frame, on: screen)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        saveCurrentFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveCurrentFrame()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        saveCurrentFrame()
    }
}
