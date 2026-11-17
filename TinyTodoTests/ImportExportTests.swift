import XCTest
@testable import TinyTodo

final class ImportExportTests: XCTestCase {
    private var database: DatabaseManager!
    private var repository: TodoRepository!
    private var service: ImportExportService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        database = try DatabaseManager(inMemory: true)
        repository = TodoRepository(dbQueue: database.dbQueue)
        service = ImportExportService(repository: repository)
    }

    func testExportIncludesPendingAndCompleted() async throws {
        let aValue = try await repository.create(title: "待办事项")
        let a = try XCTUnwrap(aValue)
        let bValue = try await repository.create(title: "已完成事项")
        let b = try XCTUnwrap(bValue)
        _ = try await repository.complete(id: b.id, at: Date(timeIntervalSince1970: 1_700_000_000))

        let file = try await service.makeExportFile()
        XCTAssertEqual(file.app, "TinyTodo")
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.todos.count, 2)
        let completed = try XCTUnwrap(file.todos.first { $0.id == b.id })
        XCTAssertEqual(completed.status, 1)
        XCTAssertNotNil(completed.completedAt)
        let pending = try XCTUnwrap(file.todos.first { $0.id == a.id })
        XCTAssertEqual(pending.status, 0)
        XCTAssertNil(pending.completedAt)
    }

    func testExportDataIsPrettyPrintedJSON() async throws {
        _ = try await repository.create(title: "导出")
        let data = try await service.exportData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"todos\""))
        XCTAssertTrue(text.contains("\n"))
    }

    func testImportRoundTripIntoEmptyDatabase() async throws {
        let aValue = try await repository.create(title: "导入我")
        let a = try XCTUnwrap(aValue)
        _ = try await repository.complete(id: a.id, at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try await service.exportData()

        let otherDatabase = try DatabaseManager(inMemory: true)
        let otherRepository = TodoRepository(dbQueue: otherDatabase.dbQueue)
        let otherService = ImportExportService(repository: otherRepository)
        let summary = try await otherService.importData(data)

        XCTAssertEqual(summary.inserted, 1)
        XCTAssertEqual(summary.updated, 0)
        let history = try await otherRepository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.map(\.title), ["导入我"])
        XCTAssertEqual(history.first?.completedAt?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 0.001)
    }

    func testImportMergesByIdWithoutDuplicating() async throws {
        let aValue = try await repository.create(title: "旧标题")
        let a = try XCTUnwrap(aValue)
        let data = try JSONEncoder().encode(ExportFile(
            app: "TinyTodo",
            version: 1,
            exportedAt: "2026-11-17T02:00:00.000Z",
            todos: [
                ExportFile.Todo(
                    id: a.id,
                    title: "新标题",
                    status: 0,
                    createdAt: "2026-11-16T02:00:00.000Z",
                    updatedAt: "2026-11-17T02:00:00.000Z",
                    completedAt: nil,
                    sortOrder: 0
                )
            ]
        ))
        let summary = try await service.importData(data)
        XCTAssertEqual(summary.inserted, 0)
        XCTAssertEqual(summary.updated, 1)
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["新标题"])
    }

    func testMalformedJSONThrows() async throws {
        let data = Data("{ not json }".utf8)
        do {
            _ = try await service.importData(data)
            XCTFail("expected malformed JSON error")
        } catch let error as ImportExportError {
            guard case .malformedJSON = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testUnsupportedVersionThrows() async throws {
        let file = ExportFile(app: "TinyTodo", version: 99, exportedAt: "2026-11-17T02:00:00.000Z", todos: [])
        let data = try JSONEncoder().encode(file)
        do {
            _ = try await service.importData(data)
            XCTFail("expected version error")
        } catch let error as ImportExportError {
            guard case .unsupportedVersion = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testEmptyTodosThrows() async throws {
        let file = ExportFile(app: "TinyTodo", version: 1, exportedAt: "2026-11-17T02:00:00.000Z", todos: [])
        let data = try JSONEncoder().encode(file)
        do {
            _ = try await service.importData(data)
            XCTFail("expected empty selection error")
        } catch let error as ImportExportError {
            guard case .emptySelection = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testImportSkipsBlankTitles() async throws {
        let file = ExportFile(
            app: "TinyTodo",
            version: 1,
            exportedAt: "2026-11-17T02:00:00.000Z",
            todos: [
                ExportFile.Todo(id: "1", title: "  ", status: 0, createdAt: "2026-11-17T02:00:00.000Z", updatedAt: "2026-11-17T02:00:00.000Z", completedAt: nil, sortOrder: 0),
                ExportFile.Todo(id: "2", title: "有效", status: 0, createdAt: "2026-11-17T02:00:00.000Z", updatedAt: "2026-11-17T02:00:00.000Z", completedAt: nil, sortOrder: 1)
            ]
        )
        let summary = try await service.importData(try JSONEncoder().encode(file))
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.inserted, 1)
    }

    func testImportDerivesCompletedAtWhenMissing() async throws {
        let file = ExportFile(
            app: "TinyTodo",
            version: 1,
            exportedAt: "2026-11-17T02:00:00.000Z",
            todos: [
                ExportFile.Todo(
                    id: "missing-completed-at",
                    title: "补全时间",
                    status: 1,
                    createdAt: "2026-11-16T02:00:00.000Z",
                    updatedAt: "2026-11-16T03:00:00.000Z",
                    completedAt: nil,
                    sortOrder: 0
                )
            ]
        )
        _ = try await service.importData(try JSONEncoder().encode(file))
        let history = try await repository.fetchHistory(HistoryQuery())
        XCTAssertNotNil(history.first?.completedAt)
        XCTAssertEqual(history.first?.updatedAt, history.first?.completedAt)
    }
}
