import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default: ⌥⇧T — the only required global shortcut.
    static let togglePanel = Self("togglePanel", initial: .init(.t, modifiers: [.option, .shift]))

    /// Optional global quick capture, configured in Settings.
    static let quickAdd = Self("quickAdd", initial: .init(.t, modifiers: [.option, .shift, .command]))
}
