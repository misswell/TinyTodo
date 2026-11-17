import Foundation
import Observation

/// Cross-view navigation state for the single panel: which tab is showing and which
/// control should take focus on the next render.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case todo
        case history
    }

    var tab: Tab = .todo
    var inputFocusRequest: Int = 0
    var searchFocusRequest: Int = 0
    var isShowingSettings: Bool = false

    func requestInputFocus() {
        tab = .todo
        inputFocusRequest &+= 1
    }

    func requestSearchFocus() {
        tab = .history
        searchFocusRequest &+= 1
    }
}
