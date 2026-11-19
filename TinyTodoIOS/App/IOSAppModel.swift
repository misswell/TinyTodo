import Foundation
import Observation
import SwiftUI

/// iOS counterpart of the Mac app model: one database, either local or inside the iCloud Drive
/// folder the user picked, with a reload when that file changes underneath us.
@MainActor
@Observable
final class IOSAppModel {
    enum Storage: Equatable {
        case local
        case iCloud(URL)
    }

    private(set) var items: [TodoItem] = []
    private(set) var stats = TodayStats()
    private(set) var storage: Storage = .local
    private(set) var database: DatabaseManager?
    private(set) var repository: TodoRepository?
    private(set) var errorMessage: String?

    let folderAccess: ICloudFolderAccess
    private var lastKnownModification: Date?

    @MainActor
    init(folderAccess: ICloudFolderAccess? = nil) {
        self.folderAccess = folderAccess ?? ICloudFolderAccess()
        openStorage()
    }

    var isUsingICloud: Bool {
        if case .iCloud = storage { return true }
        return false
    }

    var storageDescription: String {
        switch storage {
        case .local:
            return "本机"
        case let .iCloud(url):
            return "iCloud Drive · \(url.lastPathComponent)"
        }
    }

    // MARK: - Storage

    func openStorage() {
        if let folder = folderAccess.resolveFolder(), openDatabase(in: folder, mode: .iCloud) {
            storage = .iCloud(folder)
        } else {
            openDatabase(in: Self.localDirectory(), mode: .local)
            storage = .local
        }
    }

    @discardableResult
    private func openDatabase(in directory: URL, mode: StorageMode) -> Bool {
        do {
            let manager = try DatabaseManager(directory: directory, storageMode: mode)
            let repo = TodoRepository(dbQueue: manager.dbQueue)
            repo.addPendingObserver { [weak self] items in
                guard let self else { return }
                self.items = items
                Task { await self.refreshStats() }
            }
            database = manager
            repository = repo
            lastKnownModification = modificationDate(of: manager.fileURL)
            errorMessage = nil
            Task {
                self.items = (try? await repo.fetchPending()) ?? []
                await self.refreshStats()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Switches to the folder the user just picked in the Files picker.
    func useICloudFolder(_ folder: URL) {
        do {
            try folderAccess.store(folder: folder)
            let target = folder.appendingPathComponent(TinyTodoCoreInfo.databaseFileName)
            if let current = database, !FileManager.default.fileExists(atPath: target.path) {
                current.checkpoint()
                try StorageMigration.copyDatabase(from: current.fileURL, to: target)
            }
            if openDatabase(in: folder, mode: .iCloud) {
                storage = .iCloud(folder)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useLocalStorage() {
        guard case let .iCloud(folder) = storage else { return }
        let local = Self.localDirectory().appendingPathComponent(TinyTodoCoreInfo.databaseFileName)
        let remote = folder.appendingPathComponent(TinyTodoCoreInfo.databaseFileName)
        database?.checkpoint()
        if FileManager.default.fileExists(atPath: remote.path) {
            try? StorageMigration.copyDatabase(from: remote, to: local)
        }
        folderAccess.forget()
        openDatabase(in: Self.localDirectory(), mode: .local)
        storage = .local
    }

    static func localDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent(TinyTodoCoreInfo.iCloudFolderName, isDirectory: true)
    }

    // MARK: - Sync

    /// iCloud replicates the database file; when it changes underneath us the queue must be
    /// reopened, otherwise the app would keep writing into a file iCloud already replaced.
    func reloadIfFileChanged() {
        guard let database else { return }
        let current = modificationDate(of: database.fileURL)
        guard let current, current != lastKnownModification else { return }
        lastKnownModification = current
        let mode: StorageMode = isUsingICloud ? .iCloud : .local
        openDatabase(in: database.directoryURL, mode: mode)
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    // MARK: - Actions

    func add(_ title: String) {
        guard let repository else { return }
        Task {
            _ = try? await repository.create(title: title)
            await refreshStats()
        }
    }

    func complete(_ item: TodoItem) {
        guard let repository else { return }
        Task {
            _ = try? await repository.complete(id: item.id)
            await refreshStats()
        }
    }

    func restore(_ item: TodoItem) {
        guard let repository else { return }
        Task {
            _ = try? await repository.uncomplete(id: item.id, position: .end)
            await refreshStats()
        }
    }

    func delete(_ item: TodoItem) {
        guard let repository else { return }
        Task { _ = try? await repository.delete(ids: [item.id]) }
    }

    func rename(_ item: TodoItem, to title: String) {
        guard let repository else { return }
        Task { _ = try? await repository.rename(id: item.id, title: title) }
    }

    func applyOrder(_ ids: [String]) {
        guard let repository else { return }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = ids.compactMap { byID[$0] }
        Task { try? await repository.reorder(pendingIDs: ids) }
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let repository else { return }
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        items = reordered
        Task { try? await repository.reorder(pendingIDs: reordered.map(\.id)) }
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func refreshStats() async {
        guard let repository else { return }
        if let newStats = try? await repository.todayStats() {
            stats = newStats
        }
    }

    func history(search: String) async -> [TodoItem] {
        guard let repository else { return [] }
        var query = HistoryQuery()
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        query.search = trimmed.isEmpty ? nil : trimmed
        return (try? await repository.fetchHistory(query)) ?? []
    }

    func totalCompleted() async -> Int {
        guard let repository else { return 0 }
        return (try? await repository.countCompleted()) ?? 0
    }
}
