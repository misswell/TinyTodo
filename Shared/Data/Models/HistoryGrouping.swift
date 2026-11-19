import Foundation

/// Groups completed items into local-calendar days for the history page.
struct HistoryDaySection: Identifiable, Equatable, Sendable {
    /// Start of the day in the active calendar/time zone.
    let id: Date
    let items: [TodoItem]
    let calendar: Calendar
    let now: Date

    var count: Int { items.count }

    var title: String {
        DayLabel.title(for: id, calendar: calendar, now: now)
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        DayLabel.shortDate(date, calendar: calendar)
    }
}

enum HistoryGrouping {
    static func sections(
        from items: [TodoItem],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) -> [HistoryDaySection] {
        let completed = items.filter { $0.isCompleted && $0.completedAt != nil }
        let sorted = completed.sorted { lhs, rhs in
            let l = lhs.completedAt ?? .distantPast
            let r = rhs.completedAt ?? .distantPast
            if l == r { return lhs.id < rhs.id }
            return l > r
        }

        var buckets: [Date: [TodoItem]] = [:]
        for item in sorted {
            guard let completedAt = item.completedAt else { continue }
            let day = calendar.startOfDay(for: completedAt)
            buckets[day, default: []].append(item)
        }

        return buckets.keys.sorted(by: >).map { day in
            HistoryDaySection(id: day, items: buckets[day] ?? [], calendar: calendar, now: now)
        }
    }

    /// `[monthStart: count]` for the last `monthsBack` months (including the current month).
    static func monthCounts(
        timestamps: [Date],
        monthsBack: Int = 12,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) -> [(month: Date, count: Int)] {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
        var months: [Date] = []
        for offset in 0..<max(monthsBack, 1) {
            if let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth) {
                months.append(calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month)
            }
        }
        var counts: [Date: Int] = [:]
        for timestamp in timestamps {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: timestamp)) ?? timestamp
            counts[month, default: 0] += 1
        }
        return months.map { ($0, counts[$0] ?? 0) }
    }
}
