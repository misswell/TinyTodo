import AppKit
import SwiftUI

/// AppKit-backed single-line input. Wraps `NSTextView` so we can:
///  - keep IME (Pinyin) composition safe: Return during marked text confirms the candidate,
///    never creates a todo;
///  - split pasted multi-line text into several todos;
///  - keep focus for rapid consecutive input.
struct QuickInputField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onSubmit: (String) -> Void
    var onPasteLines: ([String]) -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> FocusableTextView {
        let textView = FocusableTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 1, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.maximumNumberOfLines = 1
        textView.string = text
        textView.onCommit = { [weak coordinator = context.coordinator] value in
            coordinator?.handleCommit(value)
        }
        textView.onPasteLines = { [weak coordinator = context.coordinator] lines in
            coordinator?.handlePasteLines(lines)
        }
        textView.onEscape = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEscape()
        }
        textView.setAccessibilityIdentifier("quick.input")
        context.coordinator.textView = textView
        return textView
    }

    func updateNSView(_ textView: FocusableTextView, context: Context) {
        context.coordinator.parent = self
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                window.makeFirstResponder(textView)
                textView.moveToEndOfDocument(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickInputField
        weak var textView: FocusableTextView?
        var lastFocusToken: Int = 0

        init(parent: QuickInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        func handleCommit(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                NSSound.beep()
                return
            }
            parent.onSubmit(trimmed)
            clear()
        }

        func handlePasteLines(_ lines: [String]) {
            let cleaned = lines.compactMap(TodoRepository.normalizedTitle)
            guard !cleaned.isEmpty else { return }
            parent.onPasteLines(cleaned)
            clear()
        }

        func clear() {
            parent.text = ""
            textView?.string = ""
            if let textView, let window = textView.window {
                window.makeFirstResponder(textView)
            }
        }
    }
}

/// `NSTextView` subclass with explicit Return/Enter handling.
final class FocusableTextView: NSTextView {
    var onCommit: ((String) -> Void)?
    var onPasteLines: (([String]) -> Void)?
    var onEscape: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        // Pinyin: Return confirms the candidate while composition is active.
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        commitCurrent()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertNewlineIgnoringFieldEditor(sender)
            return
        }
        commitCurrent()
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !hasMarkedText() {
            commitCurrent()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            super.cancelOperation(sender)
            return
        }
        onEscape?()
    }

    override func paste(_ sender: Any?) {
        if let raw = NSPasteboard.general.string(forType: .string) {
            let lines = Self.splitPastedText(raw)
            if lines.count > 1 {
                onPasteLines?(lines)
                return
            }
        }
        super.paste(sender)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func commitCurrent() {
        let current = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            NSSound.beep()
            return
        }
        onCommit?(current)
    }

    /// Pasting "a\nb\n- c" creates three todos; bullet prefixes are stripped.
    static func splitPastedText(_ raw: String) -> [String] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        return lines
            .map(stripBullet)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["- [ ] ", "- [x] ", "- ", "* ", "• ", "· "]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") {
            text = String(text.dropFirst(4))
        }
        return text
    }
}
