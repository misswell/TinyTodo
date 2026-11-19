import Foundation

/// JSON backup format shared by the Mac and iOS apps. Human-readable, stable field names,
/// ISO-8601 timestamps, versioned so an older client refuses a newer file.
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

enum BackupCodec {
    static let formatVersion = 1

    static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func makeExportFile(items: [TodoItem], now: Date = Date()) -> ExportFile {
        let formatter = isoFormatter()
        return ExportFile(
            app: TinyTodoCoreInfo.displayName,
            version: formatVersion,
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

    static func encode(_ file: ExportFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> (items: [TodoItem], skipped: Int) {
        let file: ExportFile
        do {
            file = try JSONDecoder().decode(ExportFile.self, from: data)
        } catch {
            throw ImportExportError.malformedJSON(error.localizedDescription)
        }
        guard file.version <= formatVersion else {
            throw ImportExportError.unsupportedVersion(file.version)
        }

        let formatter = isoFormatter()
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
            if status == .completed, completedAt == nil { completedAt = updatedAt }
            if status == .pending { completedAt = nil }
            items.append(TodoItem(
                id: raw.id.isEmpty ? UUID().uuidString : raw.id,
                title: trimmed,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
                sortOrder: raw.sortOrder
            ))
        }
        guard !items.isEmpty else { throw ImportExportError.emptySelection }
        return (items, skipped)
    }
}
