import SwiftUI
import UniformTypeIdentifiers

struct IOSHistoryView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var sections: [HistoryDaySection] = []
    @State private var search = ""
    @State private var total = 0

    var body: some View {
        Group {
            if sections.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "还没有完成的任务" : "没有匹配的历史任务",
                    systemImage: "clock"
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text(item.title)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let completedAt = item.completedAt {
                                        Text(Self.time(completedAt))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { model.restore(item); Task { await reload() } } label: {
                                        Label("恢复", systemImage: "arrow.uturn.backward")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { model.delete(item); Task { await reload() } } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .accessibilityIdentifier("ios.history.row")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: "搜索历史任务")
                .onChange(of: search) { _, _ in Task { await reload() } }
                .refreshable { await reload() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("累计完成 \(total) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
        }
        .task { await reload() }
    }

    private func reload() async {
        let items = await model.history(search: search)
        sections = HistoryGrouping.sections(from: items)
        total = await model.totalCompleted()
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
