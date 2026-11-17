import Foundation

enum AppInfo {
    static let bundleIdentifier = "app.tinytodo.TinyTodo"
    static let subsystem = "app.tinytodo.TinyTodo"
    static let displayName = "TinyTodo"
    static let tagline = "A tiny todo, always within reach."
    static let defaultPanelSize = CGSize(width: 340, height: 460)
    static let minimumPanelSize = CGSize(width: 300, height: 320)
    static let defaultsSuiteName: String? = nil

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    static var isRunningUnitTests: Bool {
        // UI tests launch the app with TINYTODO_UITEST=1 and must get a real panel.
        // Hosted unit tests inject XCTest into the app process.
        if isRunningUITests { return false }
        return NSClassFromString("XCTestCase") != nil
    }

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["TINYTODO_UITEST"] == "1"
    }
}
