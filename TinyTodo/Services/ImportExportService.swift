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

enum ImportExportError: LocalizedError {
    case unreadableFile(URL)
    case malformedJSON(String)
    case unsupportedVersion(Int)
    case emptySelection
    case nothingToExport

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(url): return "无法读取文件：\(url.lastPathComponent)"
        case let .malformedJSON(reason): return "JSON 格式错误：\(reason)"
        case let .unsupportedVersion(version): return "不支持的文件版本：v\(version)"
        case .emptySelection: return "没有找到可导入的任务"
        case .nothingToExport: return "当前没有可导出的任务"
        }
    }
}

/// JSON backup format. Human-readable, stable field names, ISO-8601 timestamps.
struct ExportFile: Codable, Equatable {
    struct Todo: Codable, Equatable {
        var id: String
        var title: String
        var status: Int
        var createdAt: String
        var updatedAt: String
        var completedAt: String?
        var sortOrder: Int
    }

    var app: String
    var version: Int
    var exportedAt: String
    var todos: [Todo]
}

final class ImportExportService {
    static let formatVersion = 1
    private let repository: TodoRepository
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "import-export")

    init(repository: TodoRepository) {
        self.repository = repository
    }

    static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    // MARK: - Export

    func makeExportFile(now: Date = Date()) async throws -> ExportFile {
        let items = try await repository.fetchAll()
        let formatter = Self.isoFormatter()
        return ExportFile(
            app: AppInfo.displayName,
            version: Self.formatVersion,
            exportedAt: formatter.string(from: now),
            todos: items.map { item in
                ExportFile.Todo(
                    id: item.id,
                    title: item.title,
                    status: item.status.rawValue,
                    createdAt: formatter.string(from: item.createdAt),
                    updatedAt: formatter.string(from: item.updatedAt),
                    completedAt: item.completedAt.map { formatter.string(from: $0) },
                    sortOrder: item.sortOrder
                )
            }
        )
    }

    func exportData() async throws -> Data {
        let file = try await makeExportFile()
        guard !file.todos.isEmpty else { throw ImportExportError.nothingToExport }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
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
        let decoder = JSONDecoder()
        let file: ExportFile
        do {
            file = try decoder.decode(ExportFile.self, from: data)
        } catch {
            throw ImportExportError.malformedJSON(error.localizedDescription)
        }
        guard file.version <= Self.formatVersion else {
            throw ImportExportError.unsupportedVersion(file.version)
        }

        let formatter = Self.isoFormatter()
        var items: [TodoItem] = []
        var skipped = 0
        for raw in file.todos {
            guard let trimmed = TodoRepository.normalizedTitle(raw.title) else {
                skipped += 1
                continue
            }
            let createdAt = formatter.date(from: raw.createdAt) ?? now
            let updatedAt = formatter.date(from: raw.updatedAt) ?? createdAt
            let status = TodoItem.Status(rawValue: raw.status) ?? .pending
            var completedAt = raw.completedAt.flatMap { formatter.date(from: $0) }
            if status == .completed, completedAt == nil {
                completedAt = updatedAt
            }
            if status == .pending {
                completedAt = nil
            }
            let item = TodoItem(
                id: raw.id.isEmpty ? UUID().uuidString : raw.id,
                title: trimmed,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
                sortOrder: raw.sortOrder
            )
            items.append(item)
        }

        guard !items.isEmpty else {
            throw ImportExportError.emptySelection
        }

        logger.debug("importing \(items.count, privacy: .public) rows")
        let counts = try await repository.upsertImported(items)
        return ImportSummary(inserted: counts.inserted, updated: counts.updated, skipped: skipped)
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: Date())
    }
}
