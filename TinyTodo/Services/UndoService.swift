import Foundation

/// Undo stack for complete / delete / reorder / rename. Lives on the main actor because it is
/// driven by menu commands and toasts.
@MainActor
@Observable
final class UndoService {
    enum ActionID: Equatable, Sendable {
        case complete(item: TodoItem)
        case delete(items: [TodoItem])
        case reorder(previousOrder: [String])
        case rename(previous: TodoItem)
    }

    struct Action: Identifiable, Sendable {
        let id: UUID
        let action: ActionID
        let label: String
        let date: Date

        init(action: ActionID, label: String, date: Date = Date()) {
            self.id = UUID()
            self.action = action
            self.label = label
            self.date = date
        }
    }

    static let maxDepth = 50

    private(set) var stack: [Action] = []
    var canUndo: Bool { !stack.isEmpty }
    var undoLabel: String? { stack.last?.label }

    /// Set by the view model; performs the inverse database mutation.
    var applyUndo: ((ActionID) async -> Void)?

    func push(_ action: ActionID, label: String) {
        stack.append(Action(action: action, label: label))
        if stack.count > Self.maxDepth {
            stack.removeFirst(stack.count - Self.maxDepth)
        }
    }

    @discardableResult
    func undo() async -> Action? {
        guard let action = stack.popLast() else { return nil }
        await applyUndo?(action.action)
        return action
    }

    func remove(_ id: UUID) {
        stack.removeAll { $0.id == id }
    }

    func clear() {
        stack.removeAll()
    }
}
