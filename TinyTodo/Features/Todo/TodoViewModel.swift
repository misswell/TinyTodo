import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TodoViewModel {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        var message: String
        var actionLabel: String?
        var isError: Bool

        init(message: String, actionLabel: String? = nil, isError: Bool = false) {
            self.id = UUID()
            self.message = message
            self.actionLabel = actionLabel
            self.isError = isError
        }
    }

    private let repository: TodoRepository
    let undoService: UndoService
    private var storeObserver: NSObjectProtocol?
    private var toastTask: Task<Void, Never>?

    private(set) var items: [TodoItem] = []
    /// Pending todos grouped by creation day, refreshed whenever `items` changes.
    private(set) var sections: [PendingSection] = []
    private(set) var stats = TodayStats()
    private(set) var toast: Toast?

    var editingID: String?
    var editingText: String = ""

    var onStatsChanged: ((TodayStats) -> Void)?
    var onItemsChanged: (([TodoItem]) -> Void)?

    init(repository: TodoRepository, undoService: UndoService) {
        self.repository = repository
        self.undoService = undoService

        repository.addListObserver { [weak self] items in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(items)
            }
        }

        undoService.applyUndo = { [weak self] action in
            await self?.applyUndo(action)
        }

        storeObserver = NotificationCenter.default.addObserver(
            forName: TodoRepository.storeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshStats() }
            }
        }
    }

    // MARK: - Loading

    func bootstrap() async {
        do {
            apply(try await repository.fetchTodoList())
            await refreshStats()
        } catch {
            presentError(error)
        }
    }

    func refreshStats() async {
        do {
            if let refreshed = try await repository.refreshVisibleDayIfNeeded() {
                apply(refreshed)
            }
            let newStats = try await repository.todayStats()
            if newStats != stats {
                stats = newStats
            }
            onStatsChanged?(stats)
        } catch {
            presentError(error)
        }
    }

    var pendingCount: Int {
        items.reduce(0) { count, item in count + (item.isCompleted ? 0 : 1) }
    }

    private func apply(_ newItems: [TodoItem]) {
        items = newItems
        sections = PendingGrouping.sections(from: newItems)
        onItemsChanged?(newItems)
    }

    // MARK: - Mutations

    func add(titles: [String]) {
        let normalized = titles.compactMap(TodoRepository.normalizedTitle)
        guard !normalized.isEmpty else { return }
        Task {
            do {
                if normalized.count == 1 {
                    _ = try await repository.create(title: normalized[0])
                } else {
                    _ = try await repository.create(titles: normalized)
                }
                await refreshStats()
            } catch {
                presentError(error)
            }
        }
    }

    func add(title: String) {
        add(titles: [title])
    }

    func complete(_ item: TodoItem) {
        guard !item.isCompleted else { return }
        Task {
            do {
                guard let completed = try await repository.complete(id: item.id) else { return }
                undoService.push(.complete(item: completed), label: "完成任务「\(item.title)」")
                presentToast("已完成「\(item.title)」", actionLabel: "撤销")
                await refreshStats()
            } catch {
                presentError(error)
            }
        }
    }

    func toggle(_ item: TodoItem) {
        if item.isCompleted {
            Task { await restore(item) }
        } else {
            complete(item)
        }
    }

    func restore(_ item: TodoItem) async {
        do {
            _ = try await repository.uncomplete(id: item.id, position: .original)
            await refreshStats()
        } catch {
            presentError(error)
        }
    }

    func delete(_ item: TodoItem) {
        Task {
            do {
                let deleted = try await repository.delete(ids: [item.id])
                guard deleted > 0 else { return }
                undoService.push(.delete(items: [item]), label: "删除任务「\(item.title)」")
                presentToast("已删除「\(item.title)」", actionLabel: "撤销")
                await refreshStats()
            } catch {
                presentError(error)
            }
        }
    }

    func delete(ids: [String]) {
        guard !ids.isEmpty else { return }
        let deletedItems = items.filter { ids.contains($0.id) }
        Task {
            do {
                let deleted = try await repository.delete(ids: ids)
                guard deleted > 0 else { return }
                undoService.push(.delete(items: deletedItems), label: "删除 \(deleted) 个任务")
                presentToast("已删除 \(deleted) 个任务", actionLabel: "撤销")
                await refreshStats()
            } catch {
                presentError(error)
            }
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !items.isEmpty else { return }
        let previousOrder = items.map(\.id)
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered.map(\.id) != previousOrder else { return }
        items = reordered
        let newOrder = reordered.map(\.id)

        Task {
            do {
                try await repository.reorder(ids: newOrder)
                undoService.push(.reorder(previousOrder: previousOrder), label: "调整任务顺序")
            } catch {
                presentError(error)
                items = reordered.sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder { return lhs.createdAt < rhs.createdAt }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
        }
    }

    /// Drag inside one day group: the row range is re-ordered, then the whole pending order is saved.
    func move(section: PendingSection, fromOffsets source: IndexSet, toOffset destination: Int) {
        let order = PendingGrouping.reordering(
            items: items,
            sectionItems: section.items,
            fromOffsets: source,
            toOffset: destination
        )
        guard order != items.map(\.id) else { return }
        let previousOrder = items.map(\.id)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = order.compactMap { byID[$0] }
        sections = PendingGrouping.sections(from: items)
        Task {
            do {
                try await repository.reorder(ids: order)
                undoService.push(.reorder(previousOrder: previousOrder), label: "调整任务顺序")
            } catch {
                presentError(error)
            }
        }
    }

    func move(_ item: TodoItem, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }

    func beginEditing(_ item: TodoItem) {
        editingID = item.id
        editingText = item.title
    }

    func commitEditing() {
        guard let id = editingID else { return }
        let text = editingText
        editingID = nil
        editingText = ""
        guard let previous = items.first(where: { $0.id == id }) else { return }
        guard let trimmed = TodoRepository.normalizedTitle(text), trimmed != previous.title else { return }

        Task {
            do {
                _ = try await repository.rename(id: id, title: trimmed)
                undoService.push(.rename(previous: previous), label: "编辑任务「\(previous.title)」")
            } catch {
                presentError(error)
            }
        }
    }

    func cancelEditing() {
        editingID = nil
        editingText = ""
    }

    // MARK: - Undo

    func undoLast() async {
        guard undoService.canUndo else {
            NSSound.beep()
            return
        }
        let undone = await undoService.undo()
        if let undone {
            presentToast("已撤销：\(undone.label)", actionLabel: nil)
        }
        await refreshStats()
    }

    private func applyUndo(_ action: UndoService.ActionID) async {
        do {
            switch action {
            case let .complete(item):
                _ = try await repository.uncomplete(id: item.id, position: .original)
            case let .delete(items):
                try await repository.restore(items: items)
            case let .reorder(previousOrder):
                try await repository.reorder(ids: previousOrder)
            case let .rename(previous):
                _ = try await repository.rename(id: previous.id, title: previous.title)
            }
            await refreshStats()
        } catch {
            presentError(error)
        }
    }

    // MARK: - Toast

    func presentToast(_ message: String, actionLabel: String?, isError: Bool = false) {
        toastTask?.cancel()
        let newToast = Toast(message: message, actionLabel: actionLabel, isError: isError)
        toast = newToast
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: isError ? 6_000_000_000 : 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == newToast.id {
                self?.toast = nil
            }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func presentError(_ error: Error) {
        presentToast("出错了：\(error.localizedDescription)", actionLabel: nil, isError: true)
    }
}
