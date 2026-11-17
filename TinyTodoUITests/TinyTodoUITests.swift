import XCTest

final class TinyTodoUITests: XCTestCase {
    private var app: XCUIApplication!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyTodoUITests-\(UUID().uuidString).sqlite")

        app = XCUIApplication()
        app.launchEnvironment["TINYTODO_UITEST"] = "1"
        app.launchEnvironment["TINYTODO_DB_PATH"] = databaseURL.path
        app.launch()
    }

    override func tearDownWithError() throws {
        if let app { app.terminate() }
        if let databaseURL {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }
        try super.tearDownWithError()
    }

    func testPanelAppearsWithTabs() {
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 15),
            "floating panel should appear on launch (app state: \(app.state.rawValue))"
        )
        XCTAssertTrue(app.buttons["tab.todo"].exists)
        XCTAssertTrue(app.buttons["tab.history"].exists)
        XCTAssertTrue(app.buttons["header.settings"].exists)
    }

    func testCreateTodoWithKeyboardAndCompleteIt() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let input = app.textViews["quick.input"].firstMatch
        if input.exists {
            input.click()
            input.typeText("写一条待办")
            input.typeText("\r")
        } else {
            // Fallback for accessibility variations: click the window and type.
            window.click()
            app.typeText("写一条待办")
            app.typeText("\r")
        }

        let row = app.otherElements["todo.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "created todo should be listed")

        let checkbox = app.buttons["todo.checkbox"].firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.click()

        app.buttons["tab.history"].click()
        let historyRow = app.otherElements["history.row"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5), "completed todo should show up in history")
    }

    func testHistoryTabShowsTotal() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.buttons["tab.history"].click()
        let total = app.staticTexts["history.total"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("累计完成"))
    }

    func testSettingsButtonOpensSettingsWindow() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.buttons["header.settings"].click()
        let settingsWindow = app.windows["TinyTodo 设置"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), "settings window should open")
        if settingsWindow.exists {
            settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        }
    }
}
