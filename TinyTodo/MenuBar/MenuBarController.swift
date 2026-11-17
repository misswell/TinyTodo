import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let panelController: FloatingPanelController

    var onOpenSettings: (() -> Void)?
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
            button.toolTip = "TinyTodo · 打开待办"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateBadge()
    }

    func update(todayCompleted: Int, pendingCount: Int) {
        self.todayCompleted = todayCompleted
        self.pendingCount = pendingCount
        updateBadge()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        if settings.showMenuBarCount, todayCompleted > 0 {
            button.title = " \(todayCompleted)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        } else {
            button.title = ""
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
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

    @objc private func quit() {
        if let onQuit {
            onQuit()
        } else {
            NSApp.terminate(nil)
        }
    }
}
