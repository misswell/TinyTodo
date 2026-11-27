import AppKit
import SwiftUI
import XCTest
@testable import TinyTodo

@MainActor
final class TodoTitleEditorTests: XCTestCase {
    func testInlineEditorOpensFocusedWithTitleSelected() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let editor = TodoTitleEditor(
            text: .constant("旧标题"),
            onSubmit: {},
            onCancel: {}
        )
        let hostingView = NSHostingView(rootView: editor)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 20)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let fieldEditor = window.firstResponder as? NSTextView,
               fieldEditor.string == "旧标题" {
                XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 3))
                window.close()
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("inline editor did not take focus and select the title")
        window.close()
    }
}
