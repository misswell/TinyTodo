import Foundation
import GRDB

/// A single todo record. Completed records are kept forever and surface as history.
struct TodoItem: Identifiable, Hashable, Sendable {
    enum Status: Int, Codable, Sendable {
        case pending = 0
        case completed = 1
    }

    var id: String
    var title: String
    var status: Status
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var sortOrder: Int

    var isCompleted: Bool { status == .completed }

    init(
        id: String = UUID().uuidString,
        title: String,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
    }
}

extension TodoItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "todos"

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let status = Column("status")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let completedAt = Column("completed_at")
        static let sortOrder = Column("sort_order")
    }

    init(row: Row) {
        self.id = row["id"]
        self.title = row["title"]
        self.status = Status(rawValue: row["status"]) ?? .pending
        self.createdAt = Date(timeIntervalSince1970: row["created_at"])
        self.updatedAt = Date(timeIntervalSince1970: row["updated_at"])
        let completed: Double? = row["completed_at"]
        self.completedAt = completed.map { Date(timeIntervalSince1970: $0) }
        self.sortOrder = row["sort_order"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["status"] = status.rawValue
        container["created_at"] = createdAt.timeIntervalSince1970
        container["updated_at"] = updatedAt.timeIntervalSince1970
        container["completed_at"] = completedAt?.timeIntervalSince1970
        container["sort_order"] = sortOrder
    }
}

extension TodoItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
    }
}
