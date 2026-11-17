import AppKit

@MainActor
enum MainMenuBuilder {
    static func build(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 TinyTodo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 TinyTodo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 TinyTodo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let newItem = NSMenuItem(title: "新建待办", action: #selector(AppDelegate.newTodo(_:)), keyEquivalent: "n")
        newItem.target = target
        fileMenu.addItem(newItem)
        let historyItem = NSMenuItem(title: "历史记录", action: #selector(AppDelegate.findHistory(_:)), keyEquivalent: "f")
        historyItem.target = target
        fileMenu.addItem(historyItem)
        fileMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: "隐藏窗口", action: #selector(AppDelegate.togglePanel(_:)), keyEquivalent: "w")
        hideItem.target = target
        fileMenu.addItem(hideItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu (standard text editing still needs the usual selectors)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let undoItem = NSMenuItem(title: "撤销", action: #selector(AppDelegate.undoLast(_:)), keyEquivalent: "z")
        undoItem.target = target
        editMenu.addItem(undoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "显示")
        // No key equivalent here: the global Carbon hotkey (⌥⇧T) already toggles the panel.
        // Duplicating it as a menu equivalent would fire the toggle twice.
        let toggleItem = NSMenuItem(title: "显示 / 隐藏待办窗口（⌥⇧T）", action: #selector(AppDelegate.togglePanel(_:)), keyEquivalent: "")
        toggleItem.target = target
        viewMenu.addItem(toggleItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuBuilder.build(target: self)

        guard !AppInfo.isRunningUnitTests else {
            // Unit tests construct their own in-memory databases.
            return
        }

        do {
            let environment = try AppEnvironment()
            self.environment = environment
            environment.start()
        } catch {
            presentStartupFailure(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.panelController.show(tab: .todo, focusInput: true)
        return false
    }

    // MARK: - Menu actions

    @objc func newTodo(_ sender: Any?) {
        environment?.panelController.show(tab: .todo, focusInput: true)
    }

    @objc func findHistory(_ sender: Any?) {
        environment?.panelController.showHistory()
    }

    @objc func undoLast(_ sender: Any?) {
        Task { await environment?.todoViewModel.undoLast() }
    }

    @objc func openSettings(_ sender: Any?) {
        environment?.openSettings()
    }

    @objc func togglePanel(_ sender: Any?) {
        environment?.panelController.toggle()
    }

    private func presentStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "TinyTodo 启动失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "退出")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
