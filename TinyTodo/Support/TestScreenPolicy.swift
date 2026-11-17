import AppKit

/// UI automation must never take over the display the user is working on.
/// In UI-test mode the panel is placed on a secondary display when one exists.
enum TestScreenPolicy {
    static var preferredScreen: NSScreen? {
        guard AppInfo.isRunningUITests else { return nil }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens.first }
        let main = NSScreen.main
        return screens.first { $0 !== main } ?? screens.first
    }

    static var preferredScreenName: String {
        preferredScreen?.localizedName ?? "none"
    }
}
