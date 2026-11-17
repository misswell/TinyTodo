import XCTest
@testable import TinyTodo

@MainActor
final class UndoServiceTests: XCTestCase {
    func testPushAndUndoAppliesAction() async {
        let service = UndoService()
        let item = TodoItem(title: "任务")
        var applied: UndoService.ActionID?
        service.applyUndo = { action in applied = action }

        service.push(.complete(item: item), label: "完成")
        XCTAssertTrue(service.canUndo)

        let undone = await service.undo()
        XCTAssertEqual(undone?.label, "完成")
        guard case let .complete(appliedItem)? = applied else {
            return XCTFail("expected complete action")
        }
        XCTAssertEqual(appliedItem.id, item.id)
        XCTAssertFalse(service.canUndo)
    }

    func testUndoStackOrderIsLIFO() async {
        let service = UndoService()
        var applied: [UndoService.ActionID] = []
        service.applyUndo = { action in applied.append(action) }

        let a = TodoItem(title: "a")
        let b = TodoItem(title: "b")
        service.push(.complete(item: a), label: "a")
        service.push(.rename(previous: b), label: "b")

        _ = await service.undo()
        _ = await service.undo()
        XCTAssertEqual(applied.count, 2)
        if case .rename = applied[0] {} else { XCTFail("expected rename first") }
        if case .complete = applied[1] {} else { XCTFail("expected complete second") }
    }

    func testStackIsCapped() {
        let service = UndoService()
        for index in 0..<(UndoService.maxDepth + 10) {
            service.push(.complete(item: TodoItem(title: "\(index)")), label: "\(index)")
        }
        XCTAssertEqual(service.stack.count, UndoService.maxDepth)
        XCTAssertEqual(service.stack.last?.label, "\(UndoService.maxDepth + 9)")
    }

    func testUndoOnEmptyStackDoesNothing() async {
        let service = UndoService()
        var called = false
        service.applyUndo = { _ in called = true }
        let result = await service.undo()
        XCTAssertNil(result)
        XCTAssertFalse(called)
    }

    func testDeleteActionKeepsAllItems() async {
        let service = UndoService()
        var captured: [TodoItem] = []
        service.applyUndo = { action in
            if case let .delete(items) = action { captured = items }
        }
        let items = [TodoItem(title: "a"), TodoItem(title: "b")]
        service.push(.delete(items: items), label: "删除 2 个任务")
        _ = await service.undo()
        XCTAssertEqual(captured.map(\.title), ["a", "b"])
    }
}
