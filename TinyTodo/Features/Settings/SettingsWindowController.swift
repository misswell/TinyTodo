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
                    resetWindowPosition: { [weak self] in self?.resetWindowPosition() }
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
}
