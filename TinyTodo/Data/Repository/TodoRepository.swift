import Foundation
import GRDB
import os

struct TodayStats: Equatable, Sendable {
    var completed: Int = 0
    var total: Int = 0

    var progressText: String { "\(completed) / \(max(total, completed))" }
}

struct HistoryQuery: Equatable, Sendable {
    var search: String?
    var start: Date?
    var end: Date?
    var limit: Int?
    var offset: Int?

    init(search: String? = nil, start: Date? = nil, end: Date? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.search = search
        self.start = start
        self.end = end
        self.limit = limit
        self.offset = offset
    }
}

enum RestorePosition: Sendable {
    /// Put the task back at the sort position it had before completion (used by undo).
    case original
    /// Append to the end of the pending list (used by an explicit "restore to todo" action).
    case end
}

/// All database access goes through this type. Reads/writes run off the main thread,
/// the pending list is pushed back through a GRDB `ValueObservation` on the main queue.
final class TodoRepository: @unchecked Sendable {
    static let storeDidChangeNotification = Notification.Name("app.tinytodo.storeDidChange")

    let dbQueue: DatabaseQueue
    private var pendingObservers: [([TodoItem]) -> Void] = []
    private var pendingObservation: AnyDatabaseCancellable?
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "repository")

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        startPendingObservation()
    }

    deinit {
        pendingObservation?.cancel()
    }

    // MARK: - Observation

    func addPendingObserver(_ observer: @escaping ([TodoItem]) -> Void) {
        pendingObservers.append(observer)
    }

    private func startPendingObservation() {
        pendingObservation?.cancel()
        let observation = ValueObservation.tracking { db in
            try Self.fetchPendingItems(db)
        }
        pendingObservation = observation.start(
            in: dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { [logger] error in
                logger.error("pending observation failed: \(String(describing: error), privacy: .public)")
            },
            onChange: { [weak self] items in
                MainActor.assumeIsolated {
                    self?.deliverPending(items)
                }
            }
        )
    }

    @MainActor
    private func deliverPending(_ items: [TodoItem]) {
        for observer in pendingObservers {
            observer(items)
        }
    }

    func fetchPending() async throws -> [TodoItem] {
        try await dbQueue.read { db in try Self.fetchPendingItems(db) }
    }

    func reloadPending() async throws -> [TodoItem] {
        try await fetchPending()
    }

    private static func fetchPendingItems(_ db: Database) throws -> [TodoItem] {
        try TodoItem.fetchAll(
            db,
            sql: """
                SELECT * FROM todos
                WHERE status = 0
                ORDER BY sort_order ASC, created_at ASC, id ASC
                """
        )
    }

    private func notifyStoreChanged() {
        // The pending list is delivered through the ValueObservation above; history and stats
        // listeners subscribe to this notification.
        NotificationCenter.default.post(name: Self.storeDidChangeNotification, object: self)
    }

    // MARK: - Mutations

    @discardableResult
    func create(title: String) async throws -> TodoItem? {
        guard let trimmed = Self.normalizedTitle(title) else { return nil }
        let item = try await dbQueue.write { db in
            try Self.insertPending(db, titles: [trimmed]).first
        }
        notifyStoreChanged()
        return item
    }

    @discardableResult
    func create(titles: [String]) async throws -> [TodoItem] {
        let normalized = titles.compactMap(Self.normalizedTitle)
        guard !normalized.isEmpty else { return [] }
        let items = try await dbQueue.write { db in
            try Self.insertPending(db, titles: normalized)
        }
        notifyStoreChanged()
        return items
    }

    @discardableResult
    func complete(id: String, at date: Date = Date()) async throws -> TodoItem? {
        let item = try await dbQueue.write { db -> TodoItem? in
            guard var item = try TodoItem.fetchOne(db, key: id) else { return nil }
            item.status = .completed
            item.completedAt = date
            item.updatedAt = date
            try item.update(db)
            return item
        }
        notifyStoreChanged()
        return item
    }

    @discardableResult
    func uncomplete(id: String, position: RestorePosition = .end) async throws -> TodoItem? {
        let item = try await dbQueue.write { db -> TodoItem? in
            guard var item = try TodoItem.fetchOne(db, key: id) else { return nil }
            item.status = .pending
            item.completedAt = nil
            item.updatedAt = Date()
            if position == .end {
                item.sortOrder = try Self.nextSortOrder(db)
            }
            try item.update(db)
            return item
        }
        notifyStoreChanged()
        return item
    }

    @discardableResult
    func rename(id: String, title: String) async throws -> TodoItem? {
        guard let trimmed = Self.normalizedTitle(title) else { return nil }
        let item = try await dbQueue.write { db -> TodoItem? in
            guard var item = try TodoItem.fetchOne(db, key: id) else { return nil }
            guard item.title != trimmed else { return item }
            item.title = trimmed
            item.updatedAt = Date()
            try item.update(db)
            return item
        }
        notifyStoreChanged()
        return item
    }

    @discardableResult
    func delete(ids: [String]) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let deleted = try await dbQueue.write { db in
            try TodoItem.deleteAll(db, keys: ids)
        }
        if deleted > 0 { notifyStoreChanged() }
        return deleted
    }

    func reorder(pendingIDs: [String]) async throws {
        guard !pendingIDs.isEmpty else { return }
        try await dbQueue.write { db in
            let now = Date().timeIntervalSince1970
            for (index, id) in pendingIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE todos SET sort_order = ?, updated_at = ? WHERE id = ? AND status = 0",
                    arguments: [index, now, id]
                )
            }
        }
        notifyStoreChanged()
    }

    /// Re-inserts previously deleted rows (undo of delete) without touching history.
    func restore(items: [TodoItem]) async throws {
        guard !items.isEmpty else { return }
        try await dbQueue.write { db in
            for item in items {
                try item.insert(db)
            }
        }
        notifyStoreChanged()
    }

    func upsertImported(_ items: [TodoItem]) async throws -> (inserted: Int, updated: Int) {
        guard !items.isEmpty else { return (0, 0) }
        let result = try await dbQueue.write { db -> (Int, Int) in
            var inserted = 0
            var updated = 0
            for item in items {
                if try TodoItem.exists(db, key: item.id) {
                    try item.update(db)
                    updated += 1
                } else {
                    try item.insert(db)
                    inserted += 1
                }
            }
            return (inserted, updated)
        }
        notifyStoreChanged()
        return result
    }

    private static func insertPending(_ db: Database, titles: [String]) throws -> [TodoItem] {
        var next = try nextSortOrder(db)
        var created: [TodoItem] = []
        created.reserveCapacity(titles.count)
        for title in titles {
            let item = TodoItem(title: title, sortOrder: next)
            try item.insert(db)
            created.append(item)
            next += 1
        }
        return created
    }

    private static func nextSortOrder(_ db: Database) throws -> Int {
        (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) FROM todos WHERE status = 0") ?? -1) + 1
    }

    // MARK: - Reads

    func fetchAll() async throws -> [TodoItem] {
        try await dbQueue.read { db in
            try TodoItem.fetchAll(
                db,
                sql: "SELECT * FROM todos ORDER BY status ASC, sort_order ASC, created_at ASC"
            )
        }
    }

    func fetchHistory(_ query: HistoryQuery) async throws -> [TodoItem] {
        let (sql, arguments) = Self.historySQL(columns: "*", query: query)
        return try await dbQueue.read { db in
            try TodoItem.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    func countCompleted(_ query: HistoryQuery = HistoryQuery()) async throws -> Int {
        var stripped = query
        stripped.limit = nil
        stripped.offset = nil
        let (sql, arguments) = Self.historySQL(columns: "COUNT(*)", query: stripped)
        return try await dbQueue.read { db in
            try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    /// Every completed timestamp; used to build month buckets and per-day counts without N queries.
    func completedTimestamps() async throws -> [Date] {
        try await dbQueue.read { db in
            try Double.fetchAll(
                db,
                sql: "SELECT completed_at FROM todos WHERE status = 1 AND completed_at IS NOT NULL"
            )
            .map { Date(timeIntervalSince1970: $0) }
        }
    }

    func todayStats(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async throws -> TodayStats {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let startEpoch = start.timeIntervalSince1970
        let endEpoch = end.timeIntervalSince1970
        return try await dbQueue.read { db in
            let completed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM todos WHERE status = 1 AND completed_at >= ? AND completed_at < ?",
                arguments: [startEpoch, endEpoch]
            ) ?? 0
            let total = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM todos
                    WHERE (created_at >= ? AND created_at < ?) OR (completed_at >= ? AND completed_at < ?)
                    """,
                arguments: [startEpoch, endEpoch, startEpoch, endEpoch]
            ) ?? 0
            return TodayStats(completed: completed, total: total)
        }
    }

    // MARK: - SQL helpers

    static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(500))
    }

    static func escapeLike(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func historySQL(columns: String, query: HistoryQuery) -> (String, StatementArguments) {
        var clauses: [String] = ["status = 1"]
        var values: [any DatabaseValueConvertible] = []

        if let rawSearch = query.search?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSearch.isEmpty {
            clauses.append("title LIKE ? ESCAPE '\\'")
            values.append("%\(escapeLike(rawSearch))%")
        }
        if let start = query.start {
            clauses.append("completed_at >= ?")
            values.append(start.timeIntervalSince1970)
        }
        if let end = query.end {
            clauses.append("completed_at < ?")
            values.append(end.timeIntervalSince1970)
        }

        var sql = "SELECT \(columns) FROM todos WHERE \(clauses.joined(separator: " AND "))"
        sql += " ORDER BY completed_at DESC, id ASC"
        if let limit = query.limit, limit > 0 {
            sql += " LIMIT \(limit)"
        }
        if let offset = query.offset, offset > 0 {
            sql += " OFFSET \(offset)"
        }
        return (sql, StatementArguments(values))
    }
}
