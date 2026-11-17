import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let database: DatabaseManager
    private let importExport: ImportExportService
    private let hotKey: HotKeyManager
    private let updateService: SoftwareUpdateService
    private let status = SettingsStatusModel()
    private var window: NSWindow?

    var onResetWindowPosition: (() -> Void)?

    init(
        settings: SettingsStore,
        database: DatabaseManager,
        importExport: ImportExportService,
        hotKey: HotKeyManager,
        updateService: SoftwareUpdateService
    ) {
        self.settings = settings
        self.database = database
        self.importExport = importExport
        self.hotKey = hotKey
        self.updateService = updateService
    }

    func show() {
        refreshStatus()
        if window == nil {
            window = makeWindow()
            if let screen = TestScreenPolicy.preferredScreen {
                let visible = screen.visibleFrame
                let size = window?.frame.size ?? .zero
                window?.setFrameOrigin(NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                ))
            } else {
                window?.center()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        hotKey.checkConflicts()
        settings.refreshLaunchAtLoginStatus()
    }

    func refreshStatus() {
        status.databaseVersion = database.databaseVersionDescription
        status.databaseSize = database.databaseSizeDescription
        status.databasePath = database.fileURL.path
        status.storageDescription = database.storageDescription
        status.isUsingICloud = database.isUsingICloud
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TinyTodo 设置"
        window.isReleasedWhenClosed = false
        window.appearance = nil
        window.contentView = NSHostingView(
            rootView: SettingsView(
                hotKey: hotKey,
                status: status,
                updateService: updateService,
                actions: SettingsActions(
                    exportJSON: { [weak self] in self?.exportJSON() },
                    importJSON: { [weak self] in self?.importJSON() },
                    revealDatabase: { [weak self] in self?.revealDatabase() },
                    copyDatabasePath: { [weak self] in self?.copyDatabasePath() },
                    resetWindowPosition: { [weak self] in self?.resetWindowPosition() },
                    chooseICloudFolder: { [weak self] in self?.chooseICloudFolder() },
                    useLocalStorage: { [weak self] in self?.useLocalStorage() }
                )
            )
            .environment(settings)
        )
        return window
    }

    // MARK: - Actions

    private func exportJSON() {
        Task {
            do {
                if let url = try await importExport.exportToUserSelectedFile() {
                    status.message = "已导出到 \(url.lastPathComponent)"
                }
            } catch {
                status.message = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func importJSON() {
        Task {
            do {
                if let summary = try await importExport.importFromUserSelectedFile() {
                    status.message = summary.description
                    refreshStatus()
                }
            } catch {
                status.message = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([database.fileURL])
    }

    private func copyDatabasePath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(database.fileURL.path, forType: .string)
        status.message = "已复制数据库路径"
    }

    private func resetWindowPosition() {
        onResetWindowPosition?()
        status.message = "窗口位置已重置"
    }

    // MARK: - iCloud storage

    private func chooseICloudFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 iCloud Drive 中的 TinyTodo 文件夹"
        panel.message = "TinyTodo 会在这个文件夹里保存 TinyTodo.sqlite，并由 iCloud 同步到其他 Mac。"
        panel.prompt = "使用此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let initial = StorageLocation.defaultICloudFolder
        if FileManager.default.fileExists(atPath: initial.path) {
            panel.directoryURL = initial
        } else if FileManager.default.fileExists(atPath: StorageLocation.iCloudDriveRoot.path) {
            panel.directoryURL = StorageLocation.iCloudDriveRoot
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        switchToICloud(folder: folder)
    }

    private func switchToICloud(folder: URL) {
        let current = database.fileURL
        let target = StorageMigration.databaseURL(in: folder)
        var preferExisting = false

        if FileManager.default.fileExists(atPath: target.path), target.standardizedFileURL != current.standardizedFileURL {
            let alert = NSAlert()
            alert.messageText = "iCloud 文件夹中已有 TinyTodo 数据"
            alert.informativeText = "可以选择使用 iCloud 上的数据，或用本机数据覆盖 iCloud。切换后需要重启 TinyTodo。"
            alert.addButton(withTitle: "使用 iCloud 数据")
            alert.addButton(withTitle: "用本机数据覆盖")
            alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                preferExisting = true
            case .alertSecondButtonReturn:
                preferExisting = false
            default:
                return
            }
        }

        database.checkpoint()
        do {
            try StorageMigration.enableICloud(
                localDatabase: current,
                iCloudFolder: folder,
                preferExistingICloudDatabase: preferExisting
            )
            StorageLocation.setMode(.iCloud, folder: folder)
            status.message = "已切换到 iCloud：\(folder.path)"
            promptRestart()
        } catch {
            status.message = "切换失败：\(error.localizedDescription)"
            showError(error)
        }
    }

    private func useLocalStorage() {
        guard database.isUsingICloud else { return }
        database.checkpoint()
        do {
            try StorageMigration.disableICloud(
                iCloudDatabase: database.fileURL,
                localDatabase: StorageMigration.localDatabaseURL()
            )
            StorageLocation.setMode(.local, folder: nil)
            status.message = "已切回本机存储"
            promptRestart()
        } catch {
            status.message = "切换失败：\(error.localizedDescription)"
            showError(error)
        }
    }

    private func promptRestart() {
        let alert = NSAlert()
        alert.messageText = "需要重启 TinyTodo"
        alert.informativeText = "存储位置已改变，重启后生效。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            restartApplication()
        }
    }

    private func restartApplication() {
        let appURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open -n \"$1\"", "sh", appURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "存储位置切换失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
