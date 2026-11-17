import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let panelController: FloatingPanelController

    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private var todayCompleted = 0
    private var pendingCount = 0

    init(settings: SettingsStore, panelController: FloatingPanelController) {
        self.settings = settings
        self.panelController = panelController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: AppInfo.displayName)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = "TinyTodo · 点击展开待办，右键打开菜单"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateBadge()
    }

    /// Left click expands the todo panel; right-click (or Control-click) opens the menu.
    static func wantsMenu(eventType: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        eventType == .rightMouseUp || modifierFlags.contains(.control)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if Self.wantsMenu(eventType: event?.type, modifierFlags: event?.modifierFlags ?? []) {
            showMenu()
        } else {
            panelController.toggleFromMenuBar(anchor: statusItem.button)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        rebuild(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    func update(todayCompleted: Int, pendingCount: Int) {
        self.todayCompleted = todayCompleted
        self.pendingCount = pendingCount
        updateBadge()
    }

    /// The badge is the number of unfinished todos, not today's completions.
    static func badgeText(pendingCount: Int, enabled: Bool) -> String {
        guard enabled, pendingCount > 0 else { return "" }
        return " \(pendingCount)"
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        button.title = Self.badgeText(pendingCount: pendingCount, enabled: settings.showMenuBarCount)
        if button.title.isEmpty {
            button.toolTip = "TinyTodo · 点击展开待办"
        } else {
            button.toolTip = "TinyTodo · 剩余 \(pendingCount) 项待办；点击展开"
        }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let summaryTitle: String
        if pendingCount == 0 && todayCompleted == 0 {
            summaryTitle = "暂无待办 · 今日完成 0 项"
        } else {
            summaryTitle = "待办 \(pendingCount) 项 · 今日完成 \(todayCompleted) 项"
        }
        let summary = NSMenuItem(title: summaryTitle, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())

        menu.addItem(item(title: panelController.isVisible ? "隐藏待办窗口" : "显示待办窗口", action: #selector(togglePanel), key: "t"))
        menu.addItem(item(title: "快速添加…", action: #selector(quickAdd), key: "n"))
        menu.addItem(item(title: "历史记录", action: #selector(showHistory), key: "f"))
        menu.addItem(.separator())
        menu.addItem(item(title: "检查更新…", action: #selector(checkForUpdates), key: ""))
        menu.addItem(item(title: "设置…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(title: "退出 TinyTodo", action: #selector(quit), key: "q"))
    }

    private func item(title: String, action: Selector, key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func quickAdd() {
        panelController.focusInput()
    }

    @objc private func showHistory() {
        panelController.showHistory()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quit() {
        if let onQuit {
            onQuit()
        } else {
            NSApp.terminate(nil)
        }
    }
}
