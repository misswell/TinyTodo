import SwiftUI

struct PanelRootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(TodoViewModel.self) private var todo
    @Environment(HistoryViewModel.self) private var history

    var onOpenSettings: () -> Void
    var onHide: () -> Void

    @State private var inputText: String = ""
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(onOpenSettings: onOpenSettings)
            Divider().opacity(0.35)

            Group {
                switch router.tab {
                case .todo:
                    TodoView()
                case .history:
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if router.tab == .todo {
                Divider().opacity(0.35)
                QuickInputBar(
                    text: $inputText,
                    focusToken: router.inputFocusRequest,
                    onSubmit: { todo.add(title: $0) },
                    onSubmitLines: { todo.add(titles: $0) },
                    onEscape: onHide
                )
            }

            Divider().opacity(0.35)
            PanelTabBar()
        }
        .background(VisualEffectBackground(material: .hudWindow))
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, router.tab == .todo ? 84 : 40)
                .animation(.easeInOut(duration: 0.18), value: todo.toast?.id)
        }
        .frame(minWidth: AppInfo.minimumPanelSize.width, minHeight: AppInfo.minimumPanelSize.height)
        .onAppear {
            Task {
                await todo.refreshStats()
                if router.tab == .history {
                    await history.reload()
                }
            }
        }
        .onChange(of: router.tab) { _, newValue in
            if newValue == .history {
                history.scheduleReload(debounce: false)
            }
        }
        .onReceive(minuteTick) { _ in
            Task { await todo.refreshStats() }
        }
    }
}
