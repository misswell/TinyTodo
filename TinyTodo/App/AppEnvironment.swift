import AppKit

enum AppearanceModeApplier {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let database: DatabaseManager
    let repository: TodoRepository
    let undoService: UndoService
    let importExport: ImportExportService
    let router: AppRouter
    let todoViewModel: TodoViewModel
    let historyViewModel: HistoryViewModel
    let windowState: WindowStateManager
    let panelController: FloatingPanelController
    let settingsWindowController: SettingsWindowController
    let hotKeyManager: HotKeyManager
    let menuBarController: MenuBarController
    private var lifecycle: AppLifecycle?
    private var started = false

    init() throws {
        let defaults: UserDefaults
        if AppInfo.isRunningUITests, let suite = UserDefaults(suiteName: "app.tinytodo.TinyTodo.uitest") {
            defaults = suite
        } else {
            defaults = .standard
        }
        settings = SettingsStore(defaults: defaults)
        database = try DatabaseManager()
        repository = TodoRepository(dbQueue: database.dbQueue)
        undoService = UndoService()
        importExport = ImportExportService(repository: repository)
        router = AppRouter()
        todoViewModel = TodoViewModel(repository: repository, undoService: undoService)
        historyViewModel = HistoryViewModel(repository: repository, undoService: undoService)
        windowState = WindowStateManager(defaults: defaults)
        panelController = FloatingPanelController(
            settings: settings,
            router: router,
            todo: todoViewModel,
            history: historyViewModel,
            windowState: windowState
        )
        hotKeyManager = HotKeyManager()
        menuBarController = MenuBarController(settings: settings, panelController: panelController)
        settingsWindowController = SettingsWindowController(
            settings: settings,
            database: database,
            importExport: importExport,
            hotKey: hotKeyManager
        )
    }

    func start() {
        guard !started else { return }
        started = true

        wireCallbacks()

        hotKeyManager.register()
        AppearanceModeApplier.apply(settings.appearance)
        panelController.applySettings()

        historyViewModel.scheduleReload(debounce: false)
        updateMenuBar()

        lifecycle = AppLifecycle(onWake: { [weak self] in
            guard let self else { return }
            self.updateMenuBar()
            Task {
                await self.todoViewModel.refreshStats()
                self.historyViewModel.scheduleReload(debounce: false)
            }
        })

        panelController.show(tab: .todo, focusInput: true)

        if AppInfo.isRunningUITests {
            let diagnostic = "windows=\(NSApp.windows.count) visible=\(panelController.isVisible) "
                + "unitTests=\(AppInfo.isRunningUnitTests) "
                + "mainScreen=\(NSScreen.main?.localizedName ?? "none") "
                + "panelScreen=\(panelController.window.screen?.localizedName ?? "none") "
                + "testScreen=\(TestScreenPolicy.preferredScreenName)"
            try? diagnostic.write(
                toFile: NSTemporaryDirectory() + "tinytodo-uitest-diagnostic.txt",
                atomically: true,
                encoding: .utf8
            )
        }
    }

    func shutdown() {
        panelController.saveCurrentFrame()
        database.vacuumIfNeeded()
    }

    func openSettings() {
        panelController.hide()
        settingsWindowController.show()
    }

    private func wireCallbacks() {
        panelController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        settingsWindowController.onResetWindowPosition = { [weak self] in
            self?.panelController.resetPosition()
        }

        hotKeyManager.onTogglePanel = { [weak self] in
            self?.panelController.toggle()
        }

        hotKeyManager.onQuickAdd = { [weak self] in
            self?.panelController.focusInput()
        }

        menuBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        menuBarController.onQuit = {
            NSApp.terminate(nil)
        }

        settings.onChange = { [weak self] change in
            self?.handleSettingsChange(change)
        }

        todoViewModel.onStatsChanged = { [weak self] _ in
            self?.updateMenuBar()
        }
        todoViewModel.onItemsChanged = { [weak self] _ in
            self?.updateMenuBar()
        }
    }

    private func handleSettingsChange(_ change: SettingsStore.Change) {
        switch change {
        case .appearance:
            AppearanceModeApplier.apply(settings.appearance)
        case .opacity, .alwaysOnTop, .acrossSpaces:
            panelController.applySettings()
        case .launchAtLogin:
            settingsWindowController.refreshStatus()
        case .menuBarCount:
            updateMenuBar()
        }
    }

    private func updateMenuBar() {
        menuBarController.update(
            todayCompleted: todoViewModel.stats.completed,
            pendingCount: todoViewModel.items.count
        )
    }
}
