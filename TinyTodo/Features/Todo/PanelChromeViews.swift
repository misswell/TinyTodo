import SwiftUI

struct PanelHeaderView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(TodoViewModel.self) private var todo
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(AppInfo.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Text(todo.stats.progressText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .help("今日进度：已完成 \(todo.stats.completed) 项，今日任务 \(max(todo.stats.total, todo.stats.completed)) 项")
                .accessibilityIdentifier("header.progress")

            Spacer(minLength: 4)

            Button {
                settings.alwaysOnTop.toggle()
            } label: {
                Image(systemName: settings.alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.alwaysOnTop ? Color.accentColor : Color.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(settings.alwaysOnTop ? "取消置顶" : "始终置顶")
            .accessibilityIdentifier("header.pin")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置（⌘,）")
            .accessibilityIdentifier("header.settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(WindowDragArea())
        .background(Color.primary.opacity(0.04))
    }
}

struct PanelTabBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(TodoViewModel.self) private var todo

    var body: some View {
        HStack(spacing: 12) {
            tabButton(title: "待办", systemImage: "list.bullet", tab: .todo)
            tabButton(title: "历史", systemImage: "clock.arrow.circlepath", tab: .history)
            Spacer(minLength: 0)
            Text("今日完成 \(todo.stats.completed) 项")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("footer.todayCompleted")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.primary.opacity(0.04))
    }

    private func tabButton(title: String, systemImage: String, tab: AppRouter.Tab) -> some View {
        Button {
            router.tab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: router.tab == tab ? .semibold : .regular))
            }
            .foregroundStyle(router.tab == tab ? Color.primary : Color.secondary)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab == .todo ? "tab.todo" : "tab.history")
    }
}

struct ToastOverlay: View {
    @Environment(TodoViewModel.self) private var todo

    var body: some View {
        if let toast = todo.toast {
            HStack(spacing: 8) {
                if toast.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Text(toast.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let action = toast.actionLabel {
                    Button(action) {
                        Task { await todo.undoLast() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .accessibilityIdentifier("toast")
        }
    }
}
