import XCTest
@testable import TinyTodo

final class HistoryGroupingTests: XCTestCase {
    private func calendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private func item(_ title: String, completedAt: Date) -> TodoItem {
        TodoItem(title: title, status: .completed, completedAt: completedAt, sortOrder: 0)
    }

    func testGroupsByLocalDayNewestFirst() {
        let calendar = calendar(timeZone: "Asia/Shanghai")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let items = [
            item("昨天 1", completedAt: yesterday.addingTimeInterval(3_600)),
            item("今天 1", completedAt: today.addingTimeInterval(3_600)),
            item("今天 2", completedAt: today.addingTimeInterval(7_200)),
            item("昨天 2", completedAt: yesterday.addingTimeInterval(7_200))
        ]

        let sections = HistoryGrouping.sections(from: items, calendar: calendar, now: now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].items.map(\.title), ["今天 2", "今天 1"])
        XCTAssertEqual(sections[1].items.map(\.title), ["昨天 2", "昨天 1"])
        XCTAssertTrue(sections[0].title.hasPrefix("今天 · 11月17日"))
        XCTAssertTrue(sections[1].title.hasPrefix("昨天 · 11月16日"))
    }

    func testSkipsPendingItems() {
        let calendar = calendar(timeZone: "Asia/Shanghai")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let pending = TodoItem(title: "未完成", status: .pending, sortOrder: 0)
        let completed = item("完成", completedAt: now)
        let sections = HistoryGrouping.sections(from: [pending, completed], calendar: calendar, now: now)
        XCTAssertEqual(sections.flatMap(\.items).map(\.title), ["完成"])
    }

    /// DST spring-forward day in Los Angeles still forms a single section.
    func testDaylightSavingBoundaryKeepsSingleSection() {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        let late = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30))!

        let sections = HistoryGrouping.sections(from: [item("早", completedAt: early), item("晚", completedAt: late)], calendar: calendar, now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].count, 2)
    }

    func testOlderYearsShowYearInTitle() {
        let calendar = calendar(timeZone: "Asia/Shanghai")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let old = calendar.date(from: DateComponents(year: 2024, month: 5, day: 1, hour: 9))!
        let sections = HistoryGrouping.sections(from: [item("旧", completedAt: old)], calendar: calendar, now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertTrue(sections[0].title.contains("2024年"))
    }

    func testMonthCountsBucketsLastTwelveMonths() {
        let calendar = calendar(timeZone: "Asia/Shanghai")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let stamps = [
            now,
            now,
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!,
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 9))!
        ]
        let counts = HistoryGrouping.monthCounts(timestamps: stamps, monthsBack: 12, calendar: calendar, now: now)
        XCTAssertEqual(counts.count, 12)
        XCTAssertEqual(counts.first?.count, 2)
        XCTAssertEqual(counts[1].count, 1)
        XCTAssertEqual(counts.reduce(0) { $0 + $1.count }, 3)
    }

    func testMonthOptionsTitles() {
        let calendar = calendar(timeZone: "Asia/Shanghai")
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let options = HistoryViewModel.buildMonthOptions(timestamps: [now], calendar: calendar, now: now)
        XCTAssertEqual(options.first?.title, "2026年11月")
        XCTAssertEqual(options.first?.count, 1)
    }
}
