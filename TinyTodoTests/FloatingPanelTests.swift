import AppKit
import XCTest
@testable import TinyTodo

/// These exercise the real AppKit panel (no UI automation required): level, Spaces
/// behavior, size limits and frame persistence are the parts that usually break.
@MainActor
final class FloatingPanelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var database: DatabaseManager!
    private var controller: FloatingPanelController!
    private var settings: SettingsStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "TinyTodoPanelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)

        settings = SettingsStore(defaults: defaults)
        database = try DatabaseManager(inMemory: true)
        let repository = TodoRepository(dbQueue: database.dbQueue)
        let undo = UndoService()
        let todo = TodoViewModel(repository: repository, undoService: undo)
        let history = HistoryViewModel(repository: repository, undoService: undo)
        controller = FloatingPanelController(
            settings: settings,
            router: AppRouter(),
            todo: todo,
            history: history,
            windowState: WindowStateManager(defaults: defaults)
        )
    }

    override func tearDownWithError() throws {
        controller = nil
        database = nil
        settings = nil
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testPanelIsFloatingWithRequiredBehaviors() {
        let panel = controller.window
        XCTAssertTrue(panel is NSPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate, "switching apps must not hide the panel")
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.minSize, AppInfo.minimumPanelSize)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertMosEqual(panel.styleMask.contains(.nonactivatingPanel), true)
    }

    func testTurningOffAlwaysOnTopFallsBackToNormalLevel() {
        settings.alwaysOnTop = false
        controller.applySettings()
        XCTAssertEqual(controller.window.level, .normal)

        settings.alwaysOnTop = true
        controller.applySettings()
        XCTAssertEqual(controller.window.level, .floating)
    }

    func testDisablingAcrossSpacesRemovesBehaviors() {
        settings.acrossSpaces = false
        controller.applySettings()
        XCTAssertFalse(controller.window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(controller.window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testOpacityAppliesToWindow() {
        settings.opacity = 0.7
        controller.applySettings()
        XCTAssertEqual(controller.window.alphaValue, 0.7, accuracy: 0.001)
    }

    func testFrameIsPersistedAndRestored() throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("No screen available")
        }
        let panel = controller.window
        let frame = CGRect(x: screen.visibleFrame.midX - 170, y: screen.visibleFrame.midY - 230, width: 340, height: 460)
        panel.setFrame(frame, display: false)
        controller.saveCurrentFrame()

        let manager = WindowStateManager(defaults: defaults)
        XCTAssertEqual(manager.restoreFrame(on: screen)?.size, frame.size)
        XCTAssertEqual(manager.restoreFrame(on: screen)?.origin.x ?? 0, frame.origin.x, accuracy: 1)
    }

    func testShowAndHideKeepsSameWindowInstance() {
        controller.show(tab: .todo, focusInput: false)
        let identity = ObjectIdentifier(controller.window)
        controller.hide()
        controller.show(tab: .history, focusInput: false)
        XCTAssertEqual(identity, ObjectIdentifier(controller.window), "the panel must be reused, never recreated")
        controller.hide()
    }

    private func XCTAssertMosEqual<T: Equatable>(_ lhs: T, _ rhs: T) {
        XCTAssertEqual(lhs, rhs)
    }
}
