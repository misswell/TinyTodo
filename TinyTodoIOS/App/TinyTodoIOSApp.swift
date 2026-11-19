import SwiftUI

@main
struct TinyTodoIOSApp: App {
    @State private var model = IOSAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reloadIfFileChanged()
                        Task { await model.refreshStats() }
                    }
                }
        }
    }
}
