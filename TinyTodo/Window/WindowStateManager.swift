import AppKit

/// Remembers the panel frame per display so multi-monitor setups restore where the user left them.
final class WindowStateManager {
    private enum Key {
        static let framesByDisplay = "window.framesByDisplay"
        static let lastDisplay = "window.lastDisplay"
    }

    private let defaults: UserDefaults
    private(set) var framesByDisplay: [String: CGRect]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.framesByDisplay = Self.loadFrames(from: defaults)
    }

    func saveFrame(_ frame: CGRect, on screen: NSScreen?) {
        guard let identifier = Self.identifier(for: screen) else { return }
        framesByDisplay[identifier] = frame
        defaults.set(Self.encode(framesByDisplay), forKey: Key.framesByDisplay)
        defaults.set(identifier, forKey: Key.lastDisplay)
    }

    func restoreFrame(on screen: NSScreen?) -> CGRect? {
        guard let identifier = Self.identifier(for: screen) else { return nil }
        return framesByDisplay[identifier]
    }

    func lastDisplayIdentifier() -> String? {
        defaults.string(forKey: Key.lastDisplay)
    }

    func reset() {
        framesByDisplay.removeAll()
        defaults.removeObject(forKey: Key.framesByDisplay)
        defaults.removeObject(forKey: Key.lastDisplay)
    }

    static func identifier(for screen: NSScreen?) -> String? {
        guard let screen else { return nil }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "screen-\(screen.localizedName)-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    private static func loadFrames(from defaults: UserDefaults) -> [String: CGRect] {
        guard let raw = defaults.dictionary(forKey: Key.framesByDisplay) as? [String: String] else { return [:] }
        var frames: [String: CGRect] = [:]
        for (identifier, encoded) in raw {
            if let frame = NSRectFromString(encoded) as CGRect?, frame.width > 0 {
                frames[identifier] = frame
            }
        }
        return frames
    }

    private static func encode(_ frames: [String: CGRect]) -> [String: String] {
        frames.mapValues { NSStringFromRect($0) }
    }
}
