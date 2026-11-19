import Foundation

/// iOS reaches the shared iCloud Drive folder through a security-scoped bookmark: iOS has no
/// `~/Library/Mobile Documents` path, so the user picks the same "TinyTodo" folder once and the
/// bookmark is resolved on every launch.
@MainActor
final class ICloudFolderAccess {
    private enum Key {
        static let bookmark = "ios.storage.iCloudBookmark"
    }

    private let defaults: UserDefaults
    private var accessingURL: URL?

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasFolder: Bool { defaults.data(forKey: Key.bookmark) != nil }

    /// The folder currently reachable, after re-resolving the bookmark. Returns nil when the
    /// bookmark is missing, stale, or the folder was removed from iCloud.
    func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Key.bookmark) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: Key.bookmark)
        }
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessingURL = url
        return url
    }

    func store(folder url: URL) throws {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else {
            throw StorageLocationError.cannotAccessFolder(url)
        }
        accessingURL = url
        let data = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Key.bookmark)
    }

    func forget() {
        stopAccessing()
        defaults.removeObject(forKey: Key.bookmark)
    }

    private func stopAccessing() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }
}

enum StorageLocationError: LocalizedError {
    case cannotAccessFolder(URL)

    var errorDescription: String? {
        switch self {
        case let .cannotAccessFolder(url): return "无法访问文件夹：\(url.lastPathComponent)"
        }
    }
}
