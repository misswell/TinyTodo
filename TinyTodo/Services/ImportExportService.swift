import AppKit
import Foundation
import os

struct ImportSummary: Equatable, Sendable {
    var inserted: Int
    var updated: Int
    var skipped: Int

    var description: String {
        "导入完成：新增 \(inserted) 项，更新 \(updated) 项，跳过 \(skipped) 项"
    }
}

final class ImportExportService {
    static let formatVersion = 1
    private let repository: TodoRepository
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "import-export")

    init(repository: TodoRepository) {
        self.repository = repository
    }

    // MARK: - Export

    func makeExportFile(now: Date = Date()) async throws -> ExportFile {
        let items = try await repository.fetchAll()
        return BackupCodec.makeExportFile(items: items, now: now)
    }

    func exportData() async throws -> Data {
        let file = try await makeExportFile()
        guard !file.todos.isEmpty else { throw ImportExportError.nothingToExport }
        return try BackupCodec.encode(file)
    }

    @MainActor
    func exportToUserSelectedFile() async throws -> URL? {
        let data = try await exportData()
        let panel = NSSavePanel()
        panel.title = "导出 TinyTodo 备份"
        panel.nameFieldStringValue = "TinyTodo-\(Self.fileStamp()).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    func importFromUserSelectedFile() async throws -> ImportSummary? {
        let panel = NSOpenPanel()
        panel.title = "导入 TinyTodo 备份"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try await importFile(at: url)
    }

    // MARK: - Import

    func importFile(at url: URL) async throws -> ImportSummary {
        guard let data = try? Data(contentsOf: url) else {
            throw ImportExportError.unreadableFile(url)
        }
        return try await importData(data)
    }

    func importData(_ data: Data, now: Date = Date()) async throws -> ImportSummary {
        let decoded = try BackupCodec.decode(data, now: now)
        logger.debug("importing \(decoded.items.count, privacy: .public) rows")
        let counts = try await repository.upsertImported(decoded.items)
        return ImportSummary(inserted: counts.inserted, updated: counts.updated, skipped: decoded.skipped)
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: Date())
    }
}
