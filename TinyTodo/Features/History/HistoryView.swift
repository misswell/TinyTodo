import SwiftUI

struct HistoryView: View {
    @Environment(HistoryViewModel.self) private var model
    @Environment(AppRouter.self) private var router
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider().opacity(0.35)
            content
            footer
        }
        .onChange(of: router.searchFocusRequest) { _, _ in
            searchFocused = true
        }
        .onAppear {
            if router.tab == .history {
                model.scheduleReload(debounce: false)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("搜索历史任务", text: Binding(
                    get: { model.searchText },
                    set: { model.searchText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .accessibilityIdentifier("history.search")
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Menu {
                Button {
                    model.filter = .all
                } label: {
                    Text(model.filter == .all ? "✓ 全部时间" : "全部时间")
                }
                Divider()
                ForEach(model.monthOptions) { option in
                    Button {
                        model.filter = .month(option.id)
                    } label: {
                        Text("\(option.title)（\(option.count)）")
                    }
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("按月份查看")
        }
        .padding(.horizontal, PanelLayout.contentInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            chip("全部", filter: .all)
            chip("今天", filter: .today)
            chip("昨天", filter: .yesterday)
            chip("7 天", filter: .last7Days)
            chip("30 天", filter: .last30Days)
            Spacer(minLength: 0)
            if case let .month(month) = model.filter {
                HStack(spacing: 3) {
                    Text(monthLabel(month))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button {
                        model.filter = .all
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, PanelLayout.contentInset)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.sections.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: model.isSearching ? "magnifyingglass" : "clock")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.quaternary)
                Text(model.emptyMessage)
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("history.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.sections) { section in
                        HistoryDateGroupView(section: section)
                    }
                }
                .padding(.horizontal, PanelLayout.contentInset)
                .padding(.vertical, 10)
            }
            .accessibilityIdentifier("history.list")
        }
    }

    private var footer: some View {
        HStack {
            Text("累计完成 \(model.totalCompleted) 项")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("history.total")
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, PanelLayout.contentInset)
        .frame(height: 30)
        .background(Color.primary.opacity(0.04))
    }

    private func chip(_ title: String, filter: HistoryViewModel.Filter) -> some View {
        let selected = model.filter == filter
        return Button {
            model.filter = filter
        } label: {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }
}
