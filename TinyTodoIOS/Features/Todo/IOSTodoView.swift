import SwiftUI

struct IOSTodoView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var editing: TodoItem?
    @State private var editTitle = ""

    private var sections: [PendingSection] {
        PendingGrouping.sections(from: model.items)
    }

    private func move(section: PendingSection, from source: IndexSet, to destination: Int) {
        let order = PendingGrouping.reordering(
            items: model.items,
            sectionItems: section.items,
            fromOffsets: source,
            toOffset: destination
        )
        model.applyOrder(order)
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                ContentUnavailableView("没有待办", systemImage: "checkmark.circle", description: Text("在下方输入后按回车保存"))
            } else {
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                row(item)
                                    .moveDisabled(item.isCompleted)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { model.delete(item) } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove { source, destination in
                                move(section: section, from: source, to: destination)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(section.items.count) 项")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            EditButton()
        }
        .alert("编辑待办", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("内容", text: $editTitle)
            Button("保存") {
                if let item = editing { model.rename(item, to: editTitle) }
                editing = nil
            }
            Button("取消", role: .cancel) { editing = nil }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                model.toggle(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isCompleted ? Color.accentColor.opacity(0.65) : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ios.todo.checkbox")

            Text(item.title)
                .font(.body)
                .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                .strikethrough(item.isCompleted, color: .secondary.opacity(0.7))
                .onTapGesture {
                    editing = item
                    editTitle = item.title
                }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("ios.todo.row")
        .accessibilityValue(item.isCompleted ? "已完成" : "未完成")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.delete(item) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
