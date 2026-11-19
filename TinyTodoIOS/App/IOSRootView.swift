import SwiftUI

struct IOSRootView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var tab: Tab = .todo

    enum Tab: Hashable {
        case todo
        case history
        case settings
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                IOSTodoView()
                    .navigationTitle("TinyTodo")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom) { IOSQuickAddBar() }
            }
            .tabItem { Label("待办", systemImage: "list.bullet") }
            .tag(Tab.todo)

            NavigationStack {
                IOSHistoryView()
                    .navigationTitle("历史")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("历史", systemImage: "clock") }
            .tag(Tab.history)

            NavigationStack {
                IOSSettingsView()
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .onChange(of: tab) { _, _ in
            model.reloadIfFileChanged()
        }
    }
}

struct IOSQuickAddBar: View {
    @Environment(IOSAppModel.self) private var model
    @AppStorage("ios.quickDraft") private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.accentColor)
            TextField("添加一个待办", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityIdentifier("ios.quick.input")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.add(trimmed)
        draft = ""
        focused = true
    }
}
