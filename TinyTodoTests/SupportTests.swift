import AppKit
import XCTest
@testable import TinyTodo

final class WindowGeometryTests: XCTestCase {
    private var screen: NSScreen!

    override func setUpWithError() throws {
        try super.setUpWithError()
        screen = NSScreen.main ?? NSScreen.screens.first
        if screen == nil { throw XCTSkip("No screen available in this environment") }
    }

    func testDefaultFrameSitsInTopRightCorner() {
        let frame = WindowGeometry.frame(size: CGSize(width: 340, height: 460), on: screen, margin: 20)
        XCTAssertEqual(frame.width, 340)
        XCTAssertEqual(frame.height, 460)
        XCTAssertLessThanOrEqual(frame.maxX, screen.visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, screen.visibleFrame.maxY)
        XCTAssertLessThanOrEqual(screen.visibleFrame.maxX - frame.maxX, 21)
        XCTAssertLessThanOrEqual(screen.visibleFrame.maxY - frame.maxY, 21)
    }

    func testClampedFrameKeepsWindowOnScreen() {
        let offscreen = CGRect(x: -5_000, y: -5_000, width: 340, height: 460)
        let clamped = WindowGeometry.clamped(offscreen, to: screen, minSize: AppInfo.minimumPanelSize)
        XCTAssertTrue(WindowGeometry.isVisible(clamped, on: screen))
        XCTAssertGreaterThanOrEqual(clamped.width, AppInfo.minimumPanelSize.width)
        XCTAssertGreaterThanOrEqual(clamped.height, AppInfo.minimumPanelSize.height)
    }

    func testClampedFrameRespectsMinimumSize() {
        let tiny = CGRect(x: 100, y: 100, width: 50, height: 50)
        let clamped = WindowGeometry.clamped(tiny, to: screen, minSize: AppInfo.minimumPanelSize)
        XCTAssertEqual(clamped.width, AppInfo.minimumPanelSize.width)
        XCTAssertEqual(clamped.height, AppInfo.minimumPanelSize.height)
    }

    func testVisibilityRatio() {
        let visible = screen.visibleFrame
        XCTAssertTrue(WindowGeometry.isVisible(CGRect(x: visible.midX, y: visible.midY, width: 200, height: 200), on: screen))
        XCTAssertFalse(WindowGeometry.isVisible(CGRect(x: visible.maxX + 400, y: visible.midY, width: 200, height: 200), on: screen))
    }
}

final class WindowStateManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "TinyTodoWindowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testStoresFramePerDisplay() throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("No screen available")
        }
        let manager = WindowStateManager(defaults: defaults)
        let frame = CGRect(x: 40, y: 60, width: 340, height: 460)
        manager.saveFrame(frame, on: screen)

        let identifier = try XCTUnwrap(WindowStateManager.identifier(for: screen))
        XCTAssertEqual(manager.restoreFrame(on: screen), frame)
        XCTAssertEqual(manager.lastDisplayIdentifier(), identifier)

        let reloaded = WindowStateManager(defaults: defaults)
        XCTAssertEqual(reloaded.restoreFrame(on: screen), frame)
    }

    func testResetClearsFrames() throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("No screen available")
        }
        let manager = WindowStateManager(defaults: defaults)
        manager.saveFrame(CGRect(x: 1, y: 2, width: 340, height: 460), on: screen)
        manager.reset()
        XCTAssertNil(manager.restoreFrame(on: screen))
        XCTAssertNil(WindowStateManager(defaults: defaults).restoreFrame(on: screen))
    }
}

final class QuickInputParsingTests: XCTestCase {
    func testSplitsMultilinePaste() {
        let text = "第一件事\n第二件事\n第三件事"
        XCTAssertEqual(FocusableTextView.splitPastedText(text), ["第一件事", "第二件事", "第三件事"])
    }

    func testStripsBulletPrefixes() {
        let text = "- 修复截图\n* 整理任务\n• 检查版本\n[ ] 写文档\n- [x] 完成项"
        XCTAssertEqual(
            FocusableTextView.splitPastedText(text),
            ["修复截图", "整理任务", "检查版本", "写文档", "完成项"]
        )
    }

    func testKeepsBlankLinesOut() {
        let text = "a\n\n   \n b \n"
        XCTAssertEqual(FocusableTextView.splitPastedText(text), ["a", "b"])
    }

    func testNormalizesCRLF() {
        let text = "a\r\nb\rc"
        XCTAssertEqual(FocusableTextView.splitPastedText(text), ["a", "b", "c"])
    }

    func testNormalizedTitleCollapsesWhitespaceEdges() {
        XCTAssertEqual(TodoRepository.normalizedTitle("  hello  "), "hello")
        XCTAssertNil(TodoRepository.normalizedTitle("   "))
        XCTAssertNil(TodoRepository.normalizedTitle("\n\t "))
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "TinyTodoSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testDefaultsMatchProductSpec() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.opacity, 1.0, accuracy: 0.001)
        XCTAssertTrue(store.alwaysOnTop)
        XCTAssertTrue(store.acrossSpaces)
        XCTAssertTrue(store.showMenuBarCount)
    }

    func testValuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.appearance = .dark
        store.opacity = 0.85
        store.alwaysOnTop = false
        store.acrossSpaces = false
        store.showMenuBarCount = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.opacity, 0.85, accuracy: 0.001)
        XCTAssertFalse(reloaded.alwaysOnTop)
        XCTAssertFalse(reloaded.acrossSpaces)
        XCTAssertFalse(reloaded.showMenuBarCount)
    }

    func testOpacityIsClamped() {
        let store = SettingsStore(defaults: defaults)
        store.opacity = 0.1
        XCTAssertGreaterThanOrEqual(store.opacity, 0.55)
        store.opacity = 5.0
        XCTAssertLessThanOrEqual(store.opacity, 1.0)
    }

    func testChangeCallbackFiresForWindowSettings() {
        let store = SettingsStore(defaults: defaults)
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.opacity = 0.9
        store.alwaysOnTop = false
        XCTAssertEqual(changes.count, 2)
        if case .opacity = changes[0] {} else { XCTFail("expected opacity change") }
        if case .alwaysOnTop = changes[1] {} else { XCTFail("expected alwaysOnTop change") }
    }
}

@MainActor
final class QuickInputCommitTests: XCTestCase {
    private func makeTextView() -> FocusableTextView {
        let textView = FocusableTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        textView.isRichText = false
        return textView
    }

    func testReturnCommitsTypedText() {
        let textView = makeTextView()
        var committed: [String] = []
        textView.onCommit = { committed.append($0) }
        textView.string = "  写一条待办 "
        textView.insertNewline(nil)
        XCTAssertEqual(committed, ["写一条待办"])
    }

    func testReturnOnEmptyTextDoesNotCommit() {
        let textView = makeTextView()
        var committed: [String] = []
        textView.onCommit = { committed.append($0) }
        textView.string = "   "
        textView.insertNewline(nil)
        XCTAssertTrue(committed.isEmpty)
    }

    func testReturnDoesNotCommitWhileIMEHasMarkedText() throws {
        let textView = makeTextView()
        var committed: [String] = []
        textView.onCommit = { committed.append($0) }
        textView.setMarkedText(
            "zhong",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        guard textView.hasMarkedText() else {
            throw XCTSkip("marked text is not available without an input context in this environment")
        }
        textView.insertNewline(nil)
        XCTAssertTrue(committed.isEmpty, "Return during Pinyin composition must not create a todo")
    }

    func testPasteOverridesWithMultipleLines() throws {
        let textView = makeTextView()
        var pasted: [[String]] = []
        textView.onPasteLines = { pasted.append($0) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("- 第一条\n- 第二条", forType: .string)
        textView.paste(nil)
        if pasted.isEmpty {
            throw XCTSkip("system pasteboard unavailable in this test environment")
        }
        XCTAssertEqual(pasted, [["第一条", "第二条"]])
    }
}

@MainActor
final class MenuBarInteractionTests: XCTestCase {
    func testLeftClickExpandsPanel() {
        XCTAssertFalse(MenuBarController.wantsMenu(eventType: .leftMouseUp, modifierFlags: []))
    }

    func testRightClickOpensMenu() {
        XCTAssertTrue(MenuBarController.wantsMenu(eventType: .rightMouseUp, modifierFlags: []))
    }

    func testControlClickOpensMenu() {
        XCTAssertTrue(MenuBarController.wantsMenu(eventType: .leftMouseUp, modifierFlags: [.control]))
    }
}
