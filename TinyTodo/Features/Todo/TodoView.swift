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
                TextField("任务内容", text: Binding(
                    get: { model.editingText },
                    set: { model.editingText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { model.commitEditing() }
                .onExitCommand { model.cancelEditing() }
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
            if !isEditing && !item.isCompleted { model.beginEditing(item) }
        }
        .contextMenu {
            if item.isCompleted {
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
