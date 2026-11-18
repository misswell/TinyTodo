import Foundation

/// Keeps whatever is typed in the quick-input field until it is submitted.
///
/// A todo half-typed when the panel is hidden, the app is quit, or another program steals focus
/// must come back when the field is shown again — losing it is the one failure a capture tool
/// cannot afford.
@MainActor
final class QuickDraftStore {
    static let shared = QuickDraftStore()

    private enum Key {
        static let draft = "quickInput.draft"
    }

    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    private let debounce: Duration

    init(defaults: UserDefaults = .standard, debounce: Duration = .milliseconds(400)) {
        self.defaults = defaults
        self.debounce = debounce
    }

    func load() -> String {
        defaults.string(forKey: Key.draft) ?? ""
    }

    /// Empty text clears the draft immediately; otherwise it is written after a short pause so
    /// typing does not hammer `UserDefaults` on every keystroke.
    func scheduleSave(_ text: String) {
        pendingSave?.cancel()
        guard !text.isEmpty else {
            defaults.removeObject(forKey: Key.draft)
            return
        }
        pendingSave = Task { [debounce, weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.defaults.set(text, forKey: Key.draft)
        }
    }

    /// Writes the current text synchronously; used when the panel hides or the app quits.
    func flush(_ text: String) {
        pendingSave?.cancel()
        if text.isEmpty {
            defaults.removeObject(forKey: Key.draft)
        } else {
            defaults.set(text, forKey: Key.draft)
        }
    }

    func clear() {
        pendingSave?.cancel()
        defaults.removeObject(forKey: Key.draft)
    }
}
