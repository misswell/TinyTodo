import Foundation

enum StorageMode: String, Codable, Sendable {
    case local
    case iCloud
}

/// Where TinyTodo keeps its SQLite file. iCloud mode stores the database inside a folder the
/// user picked in iCloud Drive; iCloud Drive itself replicates the file between Macs.
enum StorageLocation {
    static let modeKey = "storage.mode"
    static let iCloudFolderPathKey = "storage.iCloudFolderPath"

    static var iCloudDriveRoot: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return library
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
    }

    static var defaultICloudFolder: URL {
        iCloudDriveRoot.appendingPathComponent("TinyTodo", isDirectory: true)
    }

    static func mode(defaults: UserDefaults = .standard) -> StorageMode {
        StorageMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .local
    }

    static func configuredICloudFolder(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: iCloudFolderPathKey), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func isICloudPath(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Mobile Documents/com~apple~CloudDocs/")
    }

    static func setMode(_ mode: StorageMode, folder: URL?, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: modeKey)
        if let folder {
            defaults.set(folder.path, forKey: iCloudFolderPathKey)
        }
    }
}

enum StorageMigrationError: LocalizedError {
    case missingSource(URL)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingSource(url): return "找不到数据库文件：\(url.path)"
        case let .copyFailed(message): return "复制数据库失败：\(message)"
        }
    }
}

enum StorageMigration {
    static func localDatabaseURL() -> URL {
        DatabaseManager.defaultDirectoryURL.appendingPathComponent("TinyTodo.sqlite", isDirectory: false)
    }

    static func databaseURL(in folder: URL) -> URL {
        folder.appendingPathComponent("TinyTodo.sqlite", isDirectory: false)
    }

    /// Copies a database (and removes stale journals at the destination). The caller must
    /// checkpoint the live database first.
    static func copyDatabase(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw StorageMigrationError.missingSource(source)
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            removeDatabaseFiles(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw StorageMigrationError.copyFailed(error.localizedDescription)
        }
    }

    static func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Enable iCloud. When an iCloud database already exists the caller decides whether it wins.
    static func enableICloud(
        localDatabase: URL,
        iCloudFolder: URL,
        preferExistingICloudDatabase: Bool
    ) throws {
        let iCloudDatabase = databaseURL(in: iCloudFolder)
        if FileManager.default.fileExists(atPath: iCloudDatabase.path), preferExistingICloudDatabase {
            return
        }
        try copyDatabase(from: localDatabase, to: iCloudDatabase)
    }

    /// Disable iCloud by bringing the iCloud database back to Application Support. The previous
    /// local file is kept as a timestamped backup so a mistaken switch cannot destroy data.
    static func disableICloud(iCloudDatabase: URL, localDatabase: URL) throws {
        guard FileManager.default.fileExists(atPath: iCloudDatabase.path) else {
            throw StorageMigrationError.missingSource(iCloudDatabase)
        }
        if FileManager.default.fileExists(atPath: localDatabase.path) {
            let backup = localDatabase.deletingLastPathComponent()
                .appendingPathComponent("TinyTodo.local-backup-\(Int(Date().timeIntervalSince1970)).sqlite")
            try? FileManager.default.copyItem(at: localDatabase, to: backup)
        }
        try copyDatabase(from: iCloudDatabase, to: localDatabase)
    }
}
