import Foundation
import GRDB
import os

/// Owns the SQLite file, its configuration and the schema version.
///
/// Storage location:
/// `~/Library/Application Support/TinyTodo/TinyTodo.sqlite` (+ `-wal`, `-shm`).
final class DatabaseManager {
    enum DatabaseManagerError: LocalizedError {
        case cannotCreateDirectory(URL, Error)

        var errorDescription: String? {
            switch self {
            case let .cannotCreateDirectory(url, error):
                return "无法创建数据目录 \(url.path)：\(error.localizedDescription)"
            }
        }
    }

    let directoryURL: URL
    let fileURL: URL
    let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "database")

    static var defaultDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("TinyTodo", isDirectory: true)
    }

    /// Production initializer: file-backed database in Application Support.
    convenience init() throws {
        if let override = ProcessInfo.processInfo.environment["TINYTODO_DB_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            try self.init(directory: url.deletingLastPathComponent(), fileName: url.lastPathComponent)
        } else {
            try self.init(directory: Self.defaultDirectoryURL)
        }
    }

    /// File-backed database in an explicit directory (used by tests and the UI test harness).
    init(directory: URL, fileName: String = "TinyTodo.sqlite") throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DatabaseManagerError.cannotCreateDirectory(directory, error)
        }
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent(fileName)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        self.dbQueue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        try DatabaseMigration.migrator.migrate(dbQueue)
        logger.info("database ready at \(self.fileURL.path, privacy: .public)")
    }

    /// In-memory database (unit tests).
    init(inMemory: Bool) throws {
        precondition(inMemory)
        self.directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fileURL = self.directoryURL.appendingPathComponent("TinyTodo-memory.sqlite")

        let configuration = Configuration()
        self.dbQueue = try DatabaseQueue(configuration: configuration)
        try DatabaseMigration.migrator.migrate(dbQueue)
    }

    var databaseVersion: Int {
        (try? dbQueue.read { db in
            try DatabaseMigration.migrator.appliedIdentifiers(db).count
        }) ?? 0
    }

    var databaseVersionDescription: String {
        "v\(databaseVersion) / \(DatabaseMigration.latestVersion)"
    }

    var databaseSizeDescription: String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    func vacuumIfNeeded() {
        // Explicit maintenance only; never automatic cleanup of history rows.
        do {
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
        } catch {
            logger.error("wal checkpoint failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
