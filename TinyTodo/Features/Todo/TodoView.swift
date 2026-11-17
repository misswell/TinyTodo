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
            ForEach(model.items) { item in
                TodoRowView(item: item, isEditing: model.editingID == item.id)
                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                model.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 26)
        .accessibilityIdentifier("todo.list")
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text("没有待办")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("在下方输入，按 Enter 保存")
                .font(.system(size: 11))
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
        HStack(alignment: .center, spacing: 9) {
            Button {
                model.complete(item)
            } label: {
                Image(systemName: isHovering ? "checkmark.circle" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("完成任务")
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
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            if !isEditing { model.beginEditing(item) }
        }
        .contextMenu {
            Button("编辑") { model.beginEditing(item) }
            Button("上移") { model.move(item, by: -1) }
            Button("下移") { model.move(item, by: 1) }
            Button("复制文字") { copyTitle() }
            Divider()
            Button("删除", role: .destructive) { model.delete(item) }
        }
        .accessibilityIdentifier("todo.row")
        .accessibilityLabel(item.title)
    }

    private func copyTitle() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.title, forType: .string)
    }
}
