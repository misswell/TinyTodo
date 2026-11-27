import XCTest

/// End-to-end checks for the floating panel. The panel is an `NSPanel`, which macOS exposes
/// to the accessibility layer as an `AXDialog` (not an `AXWindow`), so the tests query
/// `app.dialogs` for the panel and `app.windows`/`app.dialogs` for the settings window.
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
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
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

    private var panel: XCUIElement {
        app.dialogs["TinyTodo"].firstMatch
    }

    private func diagnostic() -> String {
        (try? String(contentsOfFile: NSTemporaryDirectory() + "tinytodo-uitest-diagnostic.txt", encoding: .utf8)) ?? "none"
    }

    func testPanelAppearsWithTabs() {
        XCTAssertTrue(panel.waitForExistence(timeout: 15), "floating panel should appear on launch")
        XCTAssertTrue(app.buttons["tab.todo"].exists)
        XCTAssertTrue(app.buttons["tab.history"].exists)
        XCTAssertTrue(app.buttons["header.settings"].exists)
        XCTAssertTrue(app.buttons["header.pin"].exists)
    }

    func testCreateTodoWithKeyboardAndCompleteIt() {
        XCTAssertTrue(panel.waitForExistence(timeout: 15))

        // The input field takes focus as soon as the panel is shown.
        let input = app.textViews["quick.input"].firstMatch
        if input.exists { input.click() }
        app.typeText("写一条待办")
        app.typeKey(.return, modifierFlags: [])

        let created = app.staticTexts["写一条待办"].firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5), "created todo should be listed")

        let checkbox = app.buttons["todo.checkbox"].firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.click()

        XCTAssertTrue(
            created.waitForExistence(timeout: 5),
            "completed todo should stay in the list for the rest of today"
        )

        app.buttons["tab.history"].click()
        XCTAssertTrue(
            app.staticTexts["写一条待办"].firstMatch.waitForExistence(timeout: 5),
            "completed todo should show up in history"
        )
    }

    func testHistoryTabShowsTotal() {
        XCTAssertTrue(panel.waitForExistence(timeout: 15))
        app.buttons["tab.history"].click()

        let total = app.staticTexts["history.total"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("累计完成"))
    }

    func testDoubleClickOpensFocusedInlineEditorAndSaves() {
        XCTAssertTrue(panel.waitForExistence(timeout: 15))

        let input = app.textViews["quick.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("旧标题")
        app.typeKey(.return, modifierFlags: [])

        let row = app.descendants(matching: .any)["todo.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()

        let editor = app.textFields["todo.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "double-click should open the inline editor")
        // The editor selects the whole title on focus, so typing replaces it without an extra click.
        editor.typeText("新标题")
        editor.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["新标题"].firstMatch.waitForExistence(timeout: 5),
            "Return should commit the edited title"
        )
    }

    /// The automation window must stay off the display the user is working on.
    func testPanelUsesSecondaryDisplayWhenAvailable() throws {
        XCTAssertTrue(panel.waitForExistence(timeout: 15))
        let info = diagnostic()
        print("DIAG \(info)")

        guard NSScreen.screens.count > 1 else {
            throw XCTSkip("only one display attached")
        }
        let fields = info.split(separator: " ").reduce(into: [String: String]()) { result, token in
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
        }
        XCTAssertNotNil(fields["panelScreen"])
        XCTAssertNotEqual(fields["panelScreen"], "none")
        XCTAssertEqual(fields["panelScreen"], fields["testScreen"])
        XCTAssertNotEqual(fields["panelScreen"], fields["mainScreen"])
    }

    func testSettingsButtonOpensSettingsWindow() {
        XCTAssertTrue(panel.waitForExistence(timeout: 15))
        app.buttons["header.settings"].click()

        let byWindow = app.windows["TinyTodo 设置"]
        let byDialog = app.dialogs["TinyTodo 设置"]
        let opened = byWindow.waitForExistence(timeout: 5) || byDialog.waitForExistence(timeout: 5)
        XCTAssertTrue(opened, "settings window should open")

        if byWindow.exists {
            byWindow.buttons[XCUIIdentifierCloseWindow].click()
        } else if byDialog.exists {
            byDialog.buttons[XCUIIdentifierCloseWindow].click()
        }
    }
}
