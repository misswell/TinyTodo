import XCTest
@testable import TinyTodo

final class TodoRepositoryTests: XCTestCase {
    private var database: DatabaseManager!
    private var repository: TodoRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        database = try DatabaseManager(inMemory: true)
        repository = TodoRepository(dbQueue: database.dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        database = nil
        try super.tearDownWithError()
    }

    // MARK: - Create

    func testCreateTrimsTitleAndAppendsToEnd() async throws {
        let first = try await repository.create(title: "  写单元测试  ")
        let second = try await repository.create(title: "修复截图撤销")
        XCTAssertEqual(first?.title, "写单元测试")
        XCTAssertEqual(second?.sortOrder, 1)

        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["写单元测试", "修复截图撤销"])
    }

    func testCreateRejectsBlankTitles() async throws {
        let blank = try await repository.create(title: "   \n  ")
        XCTAssertNil(blank)
        let pending = try await repository.fetchPending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testBatchCreateSkipsBlankAndKeepsOrder() async throws {
        let created = try await repository.create(titles: ["一", "", "  ", "二", "三"])
        XCTAssertEqual(created.map(\.title), ["一", "二", "三"])
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["一", "二", "三"])
        XCTAssertEqual(pending.map(\.sortOrder), [0, 1, 2])
    }

    func testRapidSequentialCreatesDoNotLoseData() async throws {
        for index in 0..<40 {
            _ = try await repository.create(title: "任务 \(index)")
        }
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.count, 40)
        XCTAssertEqual(Set(pending.map(\.title)).count, 40)
    }

    func testConcurrentCreatesAreSerialized() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    _ = try await self.repository.create(title: "并发 \(index)")
                }
            }
            try await group.waitForAll()
        }
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.count, 30)
    }

    // MARK: - Complete / undo

    func testCompleteRemovesFromPendingAndRecordsTimestamp() async throws {
        let created = try await repository.create(title: "检查 TokenHub")
        let item = try XCTUnwrap(created)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let completedValue = try await repository.complete(id: item.id, at: completedAt)
        let completed = try XCTUnwrap(completedValue)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedAt?.timeIntervalSince1970 ?? 0, completedAt.timeIntervalSince1970, accuracy: 0.001)

        let pending = try await repository.fetchPending()
        XCTAssertTrue(pending.isEmpty)

        let history = try await repository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.map(\.id), [item.id])
        XCTAssertEqual(history.first?.completedAt?.timeIntervalSince1970 ?? 0, completedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTodoListKeepsItemsCompletedTodayAndDropsOlderCompletions() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 15))!

        let doneTodayValue = try await repository.create(title: "今日完成")
        let doneToday = try XCTUnwrap(doneTodayValue)
        let doneYesterdayValue = try await repository.create(title: "昨日完成")
        let doneYesterday = try XCTUnwrap(doneYesterdayValue)
        _ = try await repository.create(title: "仍待办")

        _ = try await repository.complete(id: doneToday.id, at: now.addingTimeInterval(-1_800))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        _ = try await repository.complete(id: doneYesterday.id, at: yesterday)

        let list = try await repository.fetchTodoList(now: now, calendar: calendar)
        XCTAssertEqual(list.map(\.title), ["今日完成", "仍待办"])
        XCTAssertEqual(list.first?.status, .completed)

        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["仍待办"])
    }

    func testUncompleteRestoresOriginalSortPosition() async throws {
        let firstValue = try await repository.create(title: "一")
        let first = try XCTUnwrap(firstValue)
        _ = try await repository.create(title: "二")
        _ = try await repository.create(title: "三")
        _ = try await repository.complete(id: first.id)

        _ = try await repository.uncomplete(id: first.id, position: .original)
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["一", "二", "三"])
        let restored = try XCTUnwrap(pending.first)
        XCTAssertEqual(restored.sortOrder, first.sortOrder)
        XCTAssertEqual(restored.status, .pending)
        XCTAssertNil(restored.completedAt)
    }

    func testUncompleteToEndAppendsToBottom() async throws {
        let firstValue = try await repository.create(title: "一")
        let first = try XCTUnwrap(firstValue)
        _ = try await repository.create(title: "二")
        _ = try await repository.complete(id: first.id)
        _ = try await repository.uncomplete(id: first.id, position: .end)

        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["二", "一"])
    }

    func testCompleteIsIdempotentForCompletedItem() async throws {
        let itemValue = try await repository.create(title: "重复完成")
        let item = try XCTUnwrap(itemValue)
        _ = try await repository.complete(id: item.id, at: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await repository.complete(id: item.id, at: Date(timeIntervalSince1970: 1_700_000_500))
        let history = try await repository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.count, 1)
    }

    // MARK: - Rename / delete / reorder

    func testRenamePersistsAndTrims() async throws {
        let itemValue = try await repository.create(title: "旧标题")
        let item = try XCTUnwrap(itemValue)
        let renamedValue = try await repository.rename(id: item.id, title: "  新标题  ")
        let renamed = try XCTUnwrap(renamedValue)
        XCTAssertEqual(renamed.title, "新标题")
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.first?.title, "新标题")
    }

    func testRenameRejectsBlankTitle() async throws {
        let itemValue = try await repository.create(title: "保留标题")
        let item = try XCTUnwrap(itemValue)
        let renamed = try await repository.rename(id: item.id, title: "   ")
        XCTAssertNil(renamed)
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.first?.title, "保留标题")
    }

    func testDeleteAndRestoreForUndo() async throws {
        let itemValue = try await repository.create(title: "删除我")
        let item = try XCTUnwrap(itemValue)
        let deletedCount = try await repository.delete(ids: [item.id])
        XCTAssertEqual(deletedCount, 1)
        let afterDelete = try await repository.fetchPending()
        XCTAssertTrue(afterDelete.isEmpty)

        try await repository.restore(items: [item])
        let pending = try await repository.fetchPending()
        XCTAssertEqual(pending.map(\.title), ["删除我"])
    }

    func testReorderPersistsNewOrder() async throws {
        _ = try await repository.create(title: "A")
        _ = try await repository.create(title: "B")
        _ = try await repository.create(title: "C")
        let pending = try await repository.fetchPending()
        let reversed = pending.map(\.id).reversed()

        try await repository.reorder(ids: Array(reversed))
        let updated = try await repository.fetchPending()
        XCTAssertEqual(updated.map(\.title), ["C", "B", "A"])
    }

    // MARK: - History queries

    func testHistorySearchMatchesSubstringAndEscapesWildcards() async throws {
        let alphaValue = try await repository.create(title: "修复 MacPilot 截图撤销问题")
        let alpha = try XCTUnwrap(alphaValue)
        let betaValue = try await repository.create(title: "100% 完成")
        let beta = try XCTUnwrap(betaValue)
        _ = try await repository.create(title: "不相关")
        _ = try await repository.complete(id: alpha.id)
        _ = try await repository.complete(id: beta.id)

        var query = HistoryQuery()
        query.search = "MacPilot"
        let macpilot = try await repository.fetchHistory(query)
        XCTAssertEqual(macpilot.map(\.id), [alpha.id])

        query.search = "100%"
        let percent = try await repository.fetchHistory(query)
        XCTAssertEqual(percent.map(\.id), [beta.id])
    }

    func testHistoryDateRangeFilters() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let aValue = try await repository.create(title: "今天完成")
        let a = try XCTUnwrap(aValue)
        let bValue = try await repository.create(title: "昨天完成")
        let b = try XCTUnwrap(bValue)
        _ = try await repository.complete(id: a.id, at: today.addingTimeInterval(3600))
        _ = try await repository.complete(id: b.id, at: yesterday.addingTimeInterval(7200))

        var todayQuery = HistoryQuery()
        todayQuery.start = today
        todayQuery.end = calendar.date(byAdding: .day, value: 1, to: today)
        let todayItems = try await repository.fetchHistory(todayQuery)
        XCTAssertEqual(todayItems.map(\.id), [a.id])

        var yesterdayQuery = HistoryQuery()
        yesterdayQuery.start = yesterday
        yesterdayQuery.end = today
        let yesterdayItems = try await repository.fetchHistory(yesterdayQuery)
        XCTAssertEqual(yesterdayItems.map(\.id), [b.id])
    }

    func testCountCompletedRespectsSearch() async throws {
        let aValue = try await repository.create(title: "alpha")
        let a = try XCTUnwrap(aValue)
        let bValue = try await repository.create(title: "beta")
        let b = try XCTUnwrap(bValue)
        _ = try await repository.complete(id: a.id)
        _ = try await repository.complete(id: b.id)

        let total = try await repository.countCompleted()
        XCTAssertEqual(total, 2)
        var query = HistoryQuery()
        query.search = "alp"
        let filtered = try await repository.countCompleted(query)
        XCTAssertEqual(filtered, 1)
    }

    func testTodayStatsCountsCreatedTodayAndCompletedToday() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.startOfDay(for: now)

        let aValue = try await repository.create(title: "今天创建")
        let a = try XCTUnwrap(aValue)
        _ = try await repository.complete(id: a.id, at: start.addingTimeInterval(100))
        _ = try await repository.create(title: "另一条待办")

        let stats = try await repository.todayStats(now: now, calendar: calendar)
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.progressText, "1 / 2")
    }

    func testCompletedTimestampsReturnsOnlyCompleted() async throws {
        let aValue = try await repository.create(title: "a")
        let a = try XCTUnwrap(aValue)
        _ = try await repository.create(title: "b")
        _ = try await repository.complete(id: a.id, at: Date(timeIntervalSince1970: 1_700_000_100))

        let stamps = try await repository.completedTimestamps()
        XCTAssertEqual(stamps.count, 1)
        XCTAssertEqual(stamps.first?.timeIntervalSince1970 ?? 0, 1_700_000_100, accuracy: 0.001)
    }

    // MARK: - Observation + notifications

    func testPendingObservationDeliversUpdates() async throws {
        let expectation = expectation(description: "pending observation")
        let lock = NSLock()
        var observedCount = 0

        repository.addListObserver { items in
            lock.lock()
            let first = observedCount == 0
            observedCount += 1
            lock.unlock()
            if first {
                XCTAssertEqual(items.count, 0)
            }
            if items.count == 1 {
                expectation.fulfill()
            }
        }

        _ = try await repository.create(title: "观察我")
        await fulfillment(of: [expectation], timeout: 5)
    }

    func testStoreChangeNotificationPosted() async throws {
        let expectation = expectation(forNotification: TodoRepository.storeDidChangeNotification, object: repository)
        _ = try await repository.create(title: "通知我")
        await fulfillment(of: [expectation], timeout: 5)
    }

    // MARK: - Persistence

    func testDataSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstDatabase = try DatabaseManager(directory: directory)
        let firstRepository = TodoRepository(dbQueue: firstDatabase.dbQueue)
        let itemValue = try await firstRepository.create(title: "重启后仍在")
        let item = try XCTUnwrap(itemValue)
        _ = try await firstRepository.complete(id: item.id, at: Date(timeIntervalSince1970: 1_700_000_000))

        let secondDatabase = try DatabaseManager(directory: directory)
        let secondRepository = TodoRepository(dbQueue: secondDatabase.dbQueue)
        let history = try await secondRepository.fetchHistory(HistoryQuery())
        XCTAssertEqual(history.map(\.title), ["重启后仍在"])
        XCTAssertEqual(history.first?.completedAt?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 0.001)
    }

    func testWALModeEnabledOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoWAL-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try DatabaseManager(directory: directory)
        let mode = try await database.dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        XCTAssertEqual(mode?.lowercased(), "wal")
    }

    func testHistoryQueryStaysFastWithTenThousandRows() async throws {
        let inMemory = try DatabaseManager(inMemory: true)
        let repo = TodoRepository(dbQueue: inMemory.dbQueue)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try await inMemory.dbQueue.write { db in
            for index in 0..<10_000 {
                var item = TodoItem(
                    title: "历史任务 \(index)",
                    status: .completed,
                    createdAt: base,
                    updatedAt: base,
                    completedAt: base.addingTimeInterval(Double(index)),
                    sortOrder: index
                )
                try item.insert(db)
            }
        }

        let started = Date()
        let page = try await repo.fetchHistory(HistoryQuery(limit: 200))
        let total = try await repo.countCompleted()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(page.count, 200)
        XCTAssertEqual(total, 10_000)
        XCTAssertLessThan(elapsed, 2.0, "history queries should stay well under the 2s budget")
    }
}
