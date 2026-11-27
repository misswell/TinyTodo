import XCTest
@testable import TinyTodo

@MainActor
final class TodoViewModelTests: XCTestCase {
    private var database: DatabaseManager!
    private var repository: TodoRepository!
    private var undoService: UndoService!
    private var viewModel: TodoViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        database = try DatabaseManager(inMemory: true)
        repository = TodoRepository(dbQueue: database.dbQueue)
        undoService = UndoService()
        viewModel = TodoViewModel(repository: repository, undoService: undoService)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        undoService = nil
        repository = nil
        database = nil
        try super.tearDownWithError()
    }

    func testCompleteThenUndoRestoresPendingItemAtOriginalPosition() async throws {
        let firstValue = try await repository.create(title: "一")
        let first = try XCTUnwrap(firstValue)
        _ = try await repository.create(title: "二")

        viewModel.complete(first)
        try await waitUntil { (try? await self.repository.fetchPending().count) == 1 }
        try await waitUntil { self.undoService.canUndo }
        let history = try await repository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.map(\.title), ["一"])

        await viewModel.undoLast()
        try await waitUntil { (try? await self.repository.fetchPending().count) == 2 }
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["一", "二"])
    }

    func testDeleteThenUndoRestoresItem() async throws {
        let value = try await repository.create(title: "重要的任务")
        let item = try XCTUnwrap(value)

        viewModel.delete(item)
        try await waitUntil { (try? await self.repository.fetchPending().isEmpty) == true }

        await viewModel.undoLast()
        try await waitUntil { (try? await self.repository.fetchPending().count) == 1 }
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["重要的任务"])
    }

    func testReorderThenUndoRestoresOrder() async throws {
        _ = try await repository.create(title: "A")
        _ = try await repository.create(title: "B")
        _ = try await repository.create(title: "C")
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["A", "B", "C"])

        viewModel.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        try await waitUntil { (try? await self.repository.fetchPending().map(\.title)) == ["B", "C", "A"] }

        await viewModel.undoLast()
        try await waitUntil { (try? await self.repository.fetchPending().map(\.title)) == ["A", "B", "C"] }
    }

    func testRenameThenUndoRestoresTitle() async throws {
        let value = try await repository.create(title: "旧标题")
        let item = try XCTUnwrap(value)

        viewModel.beginEditing(item)
        viewModel.editingText = "新标题"
        viewModel.commitEditing()
        try await waitUntil { (try? await self.repository.fetchPending().first?.title) == "新标题" }

        await viewModel.undoLast()
        try await waitUntil { (try? await self.repository.fetchPending().first?.title) == "旧标题" }
    }

    func testAddTitlesCreatesMultiplePendingItems() async throws {
        viewModel.add(titles: ["甲", "乙", "丙"])
        try await waitUntil { (try? await self.repository.fetchPending().count) == 3 }
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["甲", "乙", "丙"])
    }

    func testUndoOnEmptyStackBeepsWithoutCrash() async {
        XCTAssertFalse(undoService.canUndo)
        await viewModel.undoLast()
        XCTAssertFalse(undoService.canUndo)
    }

    func testToggleCompletesPendingItem() async throws {
        let value = try await repository.create(title: "切换")
        let item = try XCTUnwrap(value)
        viewModel.toggle(item)
        try await waitUntil { (try? await self.repository.fetchHistory(HistoryQuery()).count) == 1 }
    }

    func testCompletedItemStaysInTodoListAndRestoresInPlace() async throws {
        let firstValue = try await repository.create(title: "一")
        let first = try XCTUnwrap(firstValue)
        _ = try await repository.create(title: "二")

        viewModel.complete(first)
        try await waitUntil {
            self.viewModel.items.count == 2 && self.viewModel.items.first?.status == .completed
        }
        XCTAssertEqual(viewModel.sections.flatMap(\.items).count, 2)
        XCTAssertEqual(viewModel.pendingCount, 1)

        let completed = try XCTUnwrap(viewModel.items.first)
        viewModel.toggle(completed)
        try await waitUntil { self.viewModel.items.allSatisfy { !$0.isCompleted } }
        XCTAssertEqual(viewModel.items.map(\.title), ["一", "二"])
    }

    func testEditingCompletedItemKeepsCompletionAndChangesHistoryTitle() async throws {
        let value = try await repository.create(title: "旧标题")
        let item = try XCTUnwrap(value)

        viewModel.complete(item)
        try await waitUntil { self.viewModel.items.first?.status == .completed }

        let completed = try XCTUnwrap(viewModel.items.first)
        viewModel.beginEditing(completed)
        XCTAssertEqual(viewModel.editingText, "旧标题")
        viewModel.editingText = "新标题"
        viewModel.commitEditing()

        try await waitUntil { self.viewModel.items.first?.title == "新标题" }
        XCTAssertEqual(viewModel.items.first?.status, .completed)
        let history = try await repository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.first?.title, "新标题")
        XCTAssertEqual(history.first?.status, .completed)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("condition not satisfied within \(timeout)s", file: file, line: line)
    }
}

@MainActor
final class TodoViewModelOrderingTests: XCTestCase {
    func testMoveUpAndDownCommands() async throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TodoRepository(dbQueue: database.dbQueue)
        let undo = UndoService()
        let viewModel = TodoViewModel(repository: repository, undoService: undo)

        _ = try await repository.create(title: "A")
        _ = try await repository.create(title: "B")
        _ = try await repository.create(title: "C")

        var pending = try await repository.fetchPending()
        let b = try XCTUnwrap(pending.first { $0.title == "B" })

        viewModel.move(b, by: -1)
        try await waitForOrder(repository, ["B", "A", "C"])

        pending = try await repository.fetchPending()
        let movedB = try XCTUnwrap(pending.first { $0.title == "B" })
        viewModel.move(movedB, by: 1)
        try await waitForOrder(repository, ["A", "B", "C"])

        let firstAfter = try await repository.fetchPending().first
        viewModel.move(try XCTUnwrap(firstAfter), by: -5)
        try await waitForOrder(repository, ["A", "B", "C"])
    }

    private func waitForOrder(_ repository: TodoRepository, _ expected: [String], timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await repository.fetchPending().map(\.title)) == expected { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("order did not become \(expected)")
    }
}
