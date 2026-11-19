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

struct IOSSettingsView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var pickingFolder = false

    var body: some View {
        Form {
            Section("同步") {
                LabeledContent("当前存储", value: model.storageDescription)
                Button(model.isUsingICloud ? "更换 iCloud 文件夹…" : "使用 iCloud Drive…") {
                    pickingFolder = true
                }
                if model.isUsingICloud {
                    Button("改回本机存储", role: .destructive) { model.useLocalStorage() }
                }
                Text("在 iCloud Drive 里选择与 Mac 相同的那一个 TinyTodo 文件夹，两台设备就会读写同一个数据库。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.shortVersionString)
                Text("TinyTodo · 记录不应该成为负担")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Section("错误") {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("设置")
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url):
                model.useICloudFolder(url)
            case let .failure(error):
                model.setError(error.localizedDescription)
            }
        }
    }
}

extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
