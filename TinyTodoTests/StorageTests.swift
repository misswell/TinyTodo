import GRDB
import XCTest
@testable import TinyTodo

final class StorageLocationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "TinyTodoStorageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testModeDefaultsToLocal() {
        XCTAssertEqual(StorageLocation.mode(defaults: defaults), .local)
        XCTAssertNil(StorageLocation.configuredICloudFolder(defaults: defaults))
    }

    func testModeAndFolderPersist() {
        let folder = URL(fileURLWithPath: "/tmp/iCloud/TinyTodo", isDirectory: true)
        StorageLocation.setMode(.iCloud, folder: folder, defaults: defaults)
        XCTAssertEqual(StorageLocation.mode(defaults: defaults), .iCloud)
        XCTAssertEqual(StorageLocation.configuredICloudFolder(defaults: defaults), folder)

        StorageLocation.setMode(.local, folder: nil, defaults: defaults)
        XCTAssertEqual(StorageLocation.mode(defaults: defaults), .local)
    }

    func testICloudPathDetection() {
        XCTAssertTrue(StorageLocation.isICloudPath(URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/TinyTodo/TinyTodo.sqlite")))
        XCTAssertFalse(StorageLocation.isICloudPath(URL(fileURLWithPath: "/Users/me/Library/Application Support/TinyTodo/TinyTodo.sqlite")))
    }
}

final class DatabaseManagerStorageTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoStorage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testICloudModeUsesDeleteJournal() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let database = try DatabaseManager(directory: dir, storageMode: .iCloud)
        let mode = try await database.dbQueue.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        XCTAssertEqual(mode?.lowercased(), "delete")
        XCTAssertTrue(database.isUsingICloud)
    }

    func testLocalModeUsesWAL() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let database = try DatabaseManager(directory: dir, storageMode: .local)
        let mode = try await database.dbQueue.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        XCTAssertEqual(mode?.lowercased(), "wal")
    }

    func testCheckpointIsSafeForBothModes() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let database = try DatabaseManager(directory: dir, storageMode: .iCloud)
        database.checkpoint()
    }
}

final class StorageMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func testEnableCopiesLocalDatabaseIntoEmptyICloudFolder() throws {
        let local = root.appendingPathComponent("local/TinyTodo.sqlite")
        let folder = root.appendingPathComponent("iCloud/TinyTodo", isDirectory: true)
        try write("local-data", to: local)

        try StorageMigration.enableICloud(localDatabase: local, iCloudFolder: folder, preferExistingICloudDatabase: false)

        let copied = StorageMigration.databaseURL(in: folder)
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "local-data")
        XCTAssertEqual(try String(contentsOf: local, encoding: .utf8), "local-data")
    }

    func testEnablePrefersExistingICloudDatabaseWhenAsked() throws {
        let local = root.appendingPathComponent("local/TinyTodo.sqlite")
        let folder = root.appendingPathComponent("iCloud/TinyTodo", isDirectory: true)
        let iCloud = StorageMigration.databaseURL(in: folder)
        try write("local-data", to: local)
        try write("cloud-data", to: iCloud)

        try StorageMigration.enableICloud(localDatabase: local, iCloudFolder: folder, preferExistingICloudDatabase: true)
        XCTAssertEqual(try String(contentsOf: iCloud, encoding: .utf8), "cloud-data")

        try StorageMigration.enableICloud(localDatabase: local, iCloudFolder: folder, preferExistingICloudDatabase: false)
        XCTAssertEqual(try String(contentsOf: iCloud, encoding: .utf8), "local-data")
    }

    func testDisableBringsDataBackAndKeepsBackup() throws {
        let local = root.appendingPathComponent("local/TinyTodo.sqlite")
        let iCloud = root.appendingPathComponent("iCloud/TinyTodo/TinyTodo.sqlite")
        try write("old-local", to: local)
        try write("cloud-data", to: iCloud)

        try StorageMigration.disableICloud(iCloudDatabase: iCloud, localDatabase: local)
        XCTAssertEqual(try String(contentsOf: local, encoding: .utf8), "cloud-data")

        let backups = try FileManager.default.contentsOfDirectory(atPath: local.deletingLastPathComponent().path)
            .filter { $0.contains("local-backup") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: local.deletingLastPathComponent().appendingPathComponent(backups[0]), encoding: .utf8), "old-local")
    }

    func testCopyRemovesStaleSidecars() throws {
        let source = root.appendingPathComponent("source.sqlite")
        let destination = root.appendingPathComponent("dest.sqlite")
        try write("db", to: source)
        try write("stale-wal", to: URL(fileURLWithPath: destination.path + "-wal"))

        try StorageMigration.copyDatabase(from: source, to: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path + "-wal"))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "db")
    }
}
