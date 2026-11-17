import Foundation

enum AppInfo {
    static let bundleIdentifier = "app.tinytodo.TinyTodo"
    static let subsystem = "app.tinytodo.TinyTodo"
    static let displayName = "TinyTodo"
    static let tagline = "A tiny todo, always within reach."
    static let defaultPanelSize = CGSize(width: 340, height: 460)
    static let minimumPanelSize = CGSize(width: 300, height: 320)
    static let defaultsSuiteName: String? = nil

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    static var isRunningUnitTests: Bool {
        // Hosted unit tests inject XCTest into the app process. UI tests launch the app as a
        // plain bundle (no XCTestCase class), and `XCTestConfigurationFilePath` may be present
        // in both cases, so check for the framework itself.
        NSClassFromString("XCTestCase") != nil
    }

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["TINYTODO_UITEST"] == "1"
    }
}
