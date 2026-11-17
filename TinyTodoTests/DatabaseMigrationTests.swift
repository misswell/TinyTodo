import GRDB
import XCTest
@testable import TinyTodo

final class DatabaseMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testFreshDatabaseHasAllIndexes() throws {
        let database = try DatabaseManager(directory: directory)
        let indexes = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'todos'")
        }
        XCTAssertTrue(indexes.contains("idx_todos_status"))
        XCTAssertTrue(indexes.contains("idx_todos_completed_at"))
        XCTAssertTrue(indexes.contains("idx_todos_title"))
        XCTAssertTrue(indexes.contains("idx_todos_pending_order"))
    }

    /// Simulates upgrading an app install that only had schema v1: rows must survive the upgrade.
    func testUpgradeFromV1PreservesHistoryRows() throws {
        let url = directory.appendingPathComponent("TinyTodo.sqlite")
        let queue = try DatabaseQueue(path: url.path)

        // Build a v1-only database using a migrator that owns the same migration identifier,
        // exactly like an early TinyTodo build would have done.
        var v1Migrator = DatabaseMigrator()
        v1Migrator.registerMigration("v1_initial") { db in
            try db.create(table: "todos") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("status", .integer).notNull().defaults(to: 0)
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.column("completed_at", .double)
                table.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_todos_status", on: "todos", columns: ["status", "sort_order"])
            try db.create(index: "idx_todos_completed_at", on: "todos", columns: ["completed_at"])
        }
        try v1Migrator.migrate(queue)

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO todos (id, title, status, created_at, updated_at, completed_at, sort_order)
                VALUES ('old-1', '旧版本完成的任务', 1, 1700000000, 1700000100, 1700000100, 0)
                """)
        }

        // Now run the real migrator on that database.
        try DatabaseMigration.migrator.migrate(queue)

        let titles = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM todos WHERE status = 1")
        }
        XCTAssertEqual(titles, ["旧版本完成的任务"])

        let applied = try queue.read { db in
            try DatabaseMigration.migrator.appliedIdentifiers(db)
        }
        XCTAssertTrue(applied.contains("v1_initial"))
        XCTAssertTrue(applied.contains("v2_search_index"))
        XCTAssertTrue(applied.contains("v3_pending_order_index"))

        // Migrating again must be a no-op (relaunch safety).
        try DatabaseMigration.migrator.migrate(queue)
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM todos") ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testDatabaseManagerReportsVersion() throws {
        let database = try DatabaseManager(directory: directory)
        XCTAssertEqual(database.databaseVersionDescription, "v3 / 3")
    }
}
