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
    private(set) var stats = TodayStats()
    private(set) var toast: Toast?

    var editingID: String?
    var editingText: String = ""

    var onStatsChanged: ((TodayStats) -> Void)?
    var onItemsChanged: (([TodoItem]) -> Void)?

    init(repository: TodoRepository, undoService: UndoService) {
        self.repository = repository
        self.undoService = undoService

        repository.addPendingObserver { [weak self] items in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.items = items
                self.onItemsChanged?(items)
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
            items = try await repository.reloadPending()
            await refreshStats()
        } catch {
            presentError(error)
        }
    }

    func refreshStats() async {
        do {
            let newStats = try await repository.todayStats()
            if newStats != stats {
                stats = newStats
            }
            onStatsChanged?(stats)
        } catch {
            presentError(error)
        }
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
            _ = try await repository.uncomplete(id: item.id, position: .end)
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
                try await repository.reorder(pendingIDs: newOrder)
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
                try await repository.reorder(pendingIDs: previousOrder)
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
