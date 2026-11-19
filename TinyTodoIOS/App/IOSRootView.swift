import SwiftUI

struct IOSRootView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var tab: Tab = .todo

    enum Tab: Hashable {
        case todo
        case history
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch tab {
                case .todo:
                    IOSTodoView()
                case .history:
                    IOSHistoryView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if tab == .todo {
                    IOSQuickAddBar()
                }
            }
            .navigationTitle("TinyTodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: $tab) {
                        Text("待办").tag(Tab.todo)
                        Text("历史").tag(Tab.history)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        IOSSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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
