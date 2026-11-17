import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import Observation

/// Global hotkey. Uses Carbon `RegisterEventHotKey` through KeyboardShortcuts, which does not
/// require the Accessibility permission.
@MainActor
@Observable
final class HotKeyManager {
    private(set) var conflictMessage: String?
    private(set) var shortcutDescription: String = "⌥⇧T"
    var onTogglePanel: (() -> Void)?
    var onQuickAdd: (() -> Void)?

    private var isRegistered = false

    func register() {
        guard !isRegistered else {
            refreshShortcutDescription()
            return
        }
        isRegistered = true

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            Task { @MainActor in
                self?.onTogglePanel?()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .quickAdd) { [weak self] in
            Task { @MainActor in
                self?.onQuickAdd?()
            }
        }
        refreshShortcutDescription()
    }

    func refreshShortcutDescription() {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
            shortcutDescription = shortcut.description
        } else {
            shortcutDescription = "未设置"
        }
    }

    /// Carbon registration is exclusive across processes. We temporarily release our own
    /// registration, then try the same combination to detect another owner.
    func checkConflicts() {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) else {
            conflictMessage = "尚未设置全局快捷键，窗口只能从菜单栏打开"
            shortcutDescription = "未设置"
            return
        }
        shortcutDescription = shortcut.description

        if shortcut.isTakenBySystem {
            conflictMessage = "快捷键 \(shortcut.description) 已被 macOS 系统快捷键占用，请更换"
            return
        }

        KeyboardShortcuts.disable(.togglePanel)
        let available = Self.canRegister(shortcut: shortcut)
        KeyboardShortcuts.enable(.togglePanel)
        conflictMessage = available ? nil : "快捷键 \(shortcut.description) 已被其他应用占用，可能无法唤出窗口，请更换"
    }

    private static func canRegister(shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5444_544F), id: 1) // 'TDTO'
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        return status == noErr
    }
}
