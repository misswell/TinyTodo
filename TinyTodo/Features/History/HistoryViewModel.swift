import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    enum Filter: Hashable, Sendable {
        case all
        case today
        case yesterday
        case last7Days
        case last30Days
        case month(Date)

        var title: String {
            switch self {
            case .all: return "全部"
            case .today: return "今天"
            case .yesterday: return "昨天"
            case .last7Days: return "最近 7 天"
            case .last30Days: return "最近 30 天"
            case .month: return "按月"
            }
        }
    }

    struct MonthOption: Identifiable, Equatable, Sendable {
        let id: Date
        let title: String
        let count: Int
    }

    private let repository: TodoRepository
    private let undoService: UndoService
    private var storeObserver: NSObjectProtocol?
    private var reloadTask: Task<Void, Never>?

    private(set) var sections: [HistoryDaySection] = []
    private(set) var totalCompleted: Int = 0
    private(set) var monthOptions: [MonthOption] = []
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?

    var filter: Filter = .all {
        didSet { if filter != oldValue { scheduleReload() } }
    }

    var searchText: String = "" {
        didSet { if searchText != oldValue { scheduleReload() } }
    }

    var errorMessage: String?

    init(repository: TodoRepository, undoService: UndoService) {
        self.repository = repository
        self.undoService = undoService

        storeObserver = NotificationCenter.default.addObserver(
            forName: TodoRepository.storeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleReload(debounce: false)
            }
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var emptyMessage: String {
        if isSearching { return "没有匹配的历史任务" }
        switch filter {
        case .all: return "还没有完成的任务\n勾选一条待办，它会出现在这里"
        case .today: return "今天还没有完成的任务"
        case .yesterday: return "昨天没有完成的任务"
        case .last7Days: return "最近 7 天没有完成的任务"
        case .last30Days: return "最近 30 天没有完成的任务"
        case .month: return "这个月没有完成的任务"
        }
    }

    // MARK: - Query

    func makeQuery(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> HistoryQuery {
        var query = HistoryQuery()
        let todayStart = calendar.startOfDay(for: now)
        switch filter {
        case .all:
            break
        case .today:
            query.start = todayStart
            query.end = calendar.date(byAdding: .day, value: 1, to: todayStart)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: todayStart)
            query.start = start
            query.end = todayStart
        case .last7Days:
            query.start = calendar.date(byAdding: .day, value: -6, to: todayStart)
            query.end = calendar.date(byAdding: .day, value: 1, to: todayStart)
        case .last30Days:
            query.start = calendar.date(byAdding: .day, value: -29, to: todayStart)
            query.end = calendar.date(byAdding: .day, value: 1, to: todayStart)
        case let .month(monthStart):
            query.start = monthStart
            query.end = calendar.date(byAdding: .month, value: 1, to: monthStart)
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        query.search = trimmed.isEmpty ? nil : trimmed
        return query
    }

    // MARK: - Loading

    func scheduleReload(debounce: Bool = true) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reload(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async {
        isLoading = true
        defer { isLoading = false }
        let query = makeQuery(now: now, calendar: calendar)
        do {
            async let fetched = repository.fetchHistory(query)
            async let total = repository.countCompleted()
            async let timestamps = repository.completedTimestamps()
            let (items, totalCount, stamps) = try await (fetched, total, timestamps)
            sections = HistoryGrouping.sections(from: items, calendar: calendar, now: now)
            totalCompleted = totalCount
            monthOptions = Self.buildMonthOptions(timestamps: stamps, calendar: calendar, now: now)
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func buildMonthOptions(
        timestamps: [Date],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) -> [MonthOption] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月"
        return HistoryGrouping.monthCounts(timestamps: timestamps, calendar: calendar, now: now).map { entry in
            MonthOption(id: entry.month, title: formatter.string(from: entry.month), count: entry.count)
        }
    }

    // MARK: - Mutations

    func restore(_ item: TodoItem) {
        Task {
            do {
                _ = try await repository.uncomplete(id: item.id, position: .end)
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ item: TodoItem) {
        Task {
            do {
                let deleted = try await repository.delete(ids: [item.id])
                if deleted > 0 {
                    undoService.push(.delete(items: [item]), label: "删除历史记录「\(item.title)」")
                }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func copyTitle(_ item: TodoItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.title, forType: .string)
    }
}
