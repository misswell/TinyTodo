import Foundation

/// Pending todos split by the local day they were created on, newest day first.
///
/// The history page groups by completion day; the todo page uses the same visual rhythm so the two
/// lists read alike, while the order inside a day still follows the user's drag order.
struct PendingSection: Identifiable, Equatable, Sendable {
    /// Start of the day in the active calendar.
    let id: Date
    let items: [TodoItem]
    let calendar: Calendar
    let now: Date

    var title: String {
        DayLabel.title(for: id, calendar: calendar, now: now)
    }
}

enum DayLabel {
    static func title(for day: Date, calendar: Calendar, now: Date) -> String {
        let start = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if start == today {
            return "今天 · \(shortDate(start, calendar: calendar))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), start == yesterday {
            return "昨天 · \(shortDate(start, calendar: calendar))"
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: today)
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = sameYear ? "M月d日 EEEE" : "yyyy年M月d日 EEEE"
        return formatter.string(from: start)
    }

    static func shortDate(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day)
    }
}

enum PendingGrouping {
    static func sections(
        from items: [TodoItem],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) -> [PendingSection] {
        var buckets: [Date: [TodoItem]] = [:]
        var order: [Date] = []
        for item in items where item.status == .pending {
            let day = calendar.startOfDay(for: item.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order
            .sorted(by: >)
            .map { day in
                PendingSection(id: day, items: buckets[day] ?? [], calendar: calendar, now: now)
            }
    }

    /// Reorders one day's row range and returns the full pending order to persist.
    static func reordering(
        items: [TodoItem],
        sectionItems: [TodoItem],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [String] {
        var moved = sectionItems
        moved.move(fromOffsets: source, toOffset: destination)
        let sectionIDs = Set(sectionItems.map(\.id))
        var result: [String] = []
        var cursor = 0
        for item in items {
            if sectionIDs.contains(item.id) {
                result.append(moved[cursor].id)
                cursor += 1
            } else {
                result.append(item.id)
            }
        }
        return result
    }
}
