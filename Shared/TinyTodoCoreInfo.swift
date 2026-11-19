import Foundation

/// Identity shared by the macOS app, the iOS app and the core framework.
public enum TinyTodoCoreInfo {
    static let bundleIdentifier = "app.tinytodo.TinyTodo"
    static let iosBundleIdentifier = "app.tinytodo.TinyTodo.iOS"
    static let subsystem = "app.tinytodo.TinyTodo"
    static let displayName = "TinyTodo"
    static let iCloudFolderName = "TinyTodo"
    static let databaseFileName = "TinyTodo.sqlite"
}
