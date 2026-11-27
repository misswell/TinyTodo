import AppKit
import SwiftUI

struct TodoView: View {
    @Environment(TodoViewModel.self) private var model

    var body: some View {
        Group {
            if model.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                Section {
                    // The day label is a row, not a Section header: a plain-style macOS List
                    // draws a full-bleed separator under every section header and none of the
                    // available hiding modifiers remove it. As a row it renders clean and still
                    // scrolls with its own group.
                    sectionLabel(section, isFirst: index == 0)

                    ForEach(section.items) { item in
                        TodoRowView(item: item, isEditing: model.editingID == item.id)
                            .moveDisabled(item.isCompleted)
                            .listRowInsets(EdgeInsets(
                                top: 1,
                                leading: PanelLayout.rowInsetLeading,
                                bottom: 1,
                                trailing: PanelLayout.rowInsetTrailing
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        model.move(section: section, fromOffsets: source, toOffset: destination)
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 28)
        .padding(.top, 2)
        .frame(minHeight: 0, maxHeight: .infinity)
        .accessibilityIdentifier("todo.list")
    }

    private func sectionLabel(_ section: PendingSection, isFirst: Bool) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(section.items.count) 项")
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, isFirst ? 4 : PanelLayout.sectionTopPadding)
        .padding(.bottom, PanelLayout.sectionBottomPadding)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: PanelLayout.rowInsetLeading,
            bottom: 0,
            trailing: PanelLayout.rowInsetTrailing
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("todo.section")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.quaternary)
            Text("没有待办")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("在下方输入，按 Enter 保存")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("todo.empty")
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let isEditing: Bool

    @Environment(TodoViewModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: PanelLayout.glyphTextGap) {
            Button {
                model.toggle(item)
            } label: {
                Image(systemName: checkboxSymbol)
                    .font(.system(size: 14, weight: item.isCompleted ? .semibold : .regular))
                    .foregroundStyle(checkboxColor)
                    .frame(width: PanelLayout.glyphWidth, height: PanelLayout.glyphWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "撤销完成" : "完成任务")
            .accessibilityIdentifier("todo.checkbox")

            if isEditing {
                TodoTitleEditor(
                    text: Binding(
                        get: { model.editingText },
                        set: { model.editingText = $0 }
                    ),
                    onSubmit: { model.commitEditing() },
                    onCancel: { model.cancelEditing() }
                )
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .accessibilityIdentifier("todo.editor")
            } else {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .strikethrough(item.isCompleted, color: .secondary.opacity(0.7))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, PanelLayout.rowVerticalPadding)
        // The pill bleeds past the text rail on both sides; a background takes no part in
        // layout, so this widens the highlight without moving the glyph off the rail.
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, -PanelLayout.highlightBleed)
                .padding(.vertical, -1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            if !isEditing { model.beginEditing(item) }
        }
        .contextMenu {
            if item.isCompleted {
                Button("编辑") { model.beginEditing(item) }
                Button("撤销完成") { model.toggle(item) }
                Button("复制文字") { copyTitle() }
                Divider()
                Button("删除", role: .destructive) { model.delete(item) }
            } else {
                Button("编辑") { model.beginEditing(item) }
                Button("上移") { model.move(item, by: -1) }
                Button("下移") { model.move(item, by: 1) }
                Button("复制文字") { copyTitle() }
                Divider()
                Button("删除", role: .destructive) { model.delete(item) }
            }
        }
        .accessibilityIdentifier("todo.row")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.isCompleted ? "已完成" : "未完成")
    }

    private var checkboxSymbol: String {
        if item.isCompleted { return "checkmark.circle.fill" }
        return isHovering ? "checkmark.circle" : "circle"
    }

    private var checkboxColor: Color {
        if item.isCompleted { return Color.accentColor.opacity(0.65) }
        return isHovering ? Color.accentColor : Color.secondary.opacity(0.75)
    }

    private func copyTitle() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.title, forType: .string)
    }
}

/// Inline title editor backed by `NSTextField`.
///
/// A plain SwiftUI `TextField` appeared in the row but did not become first responder, so a
/// double-click looked like a no-op and typing still went to the quick-input field. This view
/// focuses itself as soon as it is attached to the window, selects the whole title, and commits
/// on Return or focus loss.
struct TodoTitleEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("todo.editor")
        return field
    }

    func updateNSView(_ field: AutoFocusTextField, context: Context) {
        context.coordinator.parent = self
        // Do not overwrite what the field editor is currently editing; only sync externally
        // driven changes while the field is idle.
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoTitleEditor
        private var isCancelling = false

        init(parent: TodoTitleEditor) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                isCancelling = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if isCancelling {
                isCancelling = false
                return
            }
            // Clicking another row or leaving the panel commits instead of silently keeping a
            // half-edited title on screen.
            parent.onSubmit()
        }
    }
}

final class AutoFocusTextField: NSTextField {
    private var didRequestFocus = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 17)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didRequestFocus, window != nil else { return }
        didRequestFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}
