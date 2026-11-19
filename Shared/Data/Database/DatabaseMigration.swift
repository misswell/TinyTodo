import Foundation
import GRDB

/// Versioned schema. History rows must survive every future migration, so migrations are
/// additive only: never drop `todos` rows, never rewrite `completed_at` values.
enum DatabaseMigration {
    static let latestVersion = 3

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: TodoItem.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("status", .integer).notNull().defaults(to: TodoItem.Status.pending.rawValue)
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.column("completed_at", .double)
                table.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_todos_status", on: TodoItem.databaseTableName, columns: ["status", "sort_order"])
            try db.create(index: "idx_todos_completed_at", on: TodoItem.databaseTableName, columns: ["completed_at"])
        }

        migrator.registerMigration("v2_search_index") { db in
            // History search scans `title`; the index is additive and history rows are untouched.
            try db.create(index: "idx_todos_title", on: TodoItem.databaseTableName, columns: ["title"])
        }

        migrator.registerMigration("v3_pending_order_index") { db in
            // Pending list is ordered by (sort_order, created_at); cover that exact ordering.
            try db.create(index: "idx_todos_pending_order", on: TodoItem.databaseTableName, columns: ["status", "sort_order", "created_at"])
        }

        return migrator
    }
}
