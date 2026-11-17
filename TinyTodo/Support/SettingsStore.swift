import Foundation

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
///
/// All UI-facing properties are `@Observable`; window/hotkey side effects are delivered
/// through `onChange` so AppKit objects stay out of the views.
@MainActor
@Observable
final class SettingsStore {
    enum Change {
        case appearance
        case opacity
        case alwaysOnTop
        case acrossSpaces
        case launchAtLogin
        case menuBarCount
        case autoCheckForUpdates
    }

    private enum Key {
        static let appearance = "settings.appearance"
        static let opacity = "settings.opacity"
        static let alwaysOnTop = "settings.alwaysOnTop"
        static let acrossSpaces = "settings.acrossSpaces"
        static let launchAtLogin = "settings.launchAtLogin"
        static let menuBarCount = "settings.menuBarCount"
        static let autoCheckForUpdates = "settings.autoCheckForUpdates"
        static let didShowWelcome = "settings.didShowWelcome"
    }

    private let defaults: UserDefaults
    private var isRestoring = true

    var onChange: ((Change) -> Void)?

    var appearance: AppearanceMode {
        didSet {
            guard !isRestoring else { return }
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            onChange?(.appearance)
        }
    }

    var opacity: Double {
        didSet {
            guard !isRestoring else { return }
            let clamped = min(max(opacity, 0.55), 1.0)
            if clamped != opacity { opacity = clamped; return }
            defaults.set(clamped, forKey: Key.opacity)
            onChange?(.opacity)
        }
    }

    var alwaysOnTop: Bool {
        didSet {
            guard !isRestoring else { return }
            defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop)
            onChange?(.alwaysOnTop)
        }
    }

    var acrossSpaces: Bool {
        didSet {
            guard !isRestoring else { return }
            defaults.set(acrossSpaces, forKey: Key.acrossSpaces)
            onChange?(.acrossSpaces)
        }
    }

    var showMenuBarCount: Bool {
        didSet {
            guard !isRestoring else { return }
            defaults.set(showMenuBarCount, forKey: Key.menuBarCount)
            onChange?(.menuBarCount)
        }
    }

    var autoCheckForUpdates: Bool {
        didSet {
            guard !isRestoring else { return }
            defaults.set(autoCheckForUpdates, forKey: Key.autoCheckForUpdates)
            onChange?(.autoCheckForUpdates)
        }
    }

    /// Mirrors `SMAppService.mainApp` status. Writes go through `StartupService`.
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        let storedOpacity = defaults.object(forKey: Key.opacity) as? Double
        self.opacity = min(max(storedOpacity ?? 1.0, 0.55), 1.0)
        self.alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        self.acrossSpaces = defaults.object(forKey: Key.acrossSpaces) as? Bool ?? true
        self.showMenuBarCount = defaults.object(forKey: Key.menuBarCount) as? Bool ?? true
        self.autoCheckForUpdates = defaults.object(forKey: Key.autoCheckForUpdates) as? Bool ?? true
        self.launchAtLogin = StartupService.isEnabled
        self.isRestoring = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try StartupService.setEnabled(enabled)
            launchAtLogin = StartupService.isEnabled
            launchAtLoginError = nil
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            onChange?(.launchAtLogin)
        } catch {
            launchAtLogin = StartupService.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = StartupService.isEnabled
    }
}
