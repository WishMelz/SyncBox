import XCTest
import Observation
@testable import SyncBoxCore

@MainActor
final class MessageHistoryTests: XCTestCase {
    func testThreeThousandMessagesContinuePastFirstThirtyUntilExhausted() async throws {
        let records = (1...3000).map { n in
            Message(id: String(format: "%04d", n), content: "消息 \(n)",
                    createdAt: "2026-11-09T00:00:00.000Z", isStarred: false, senderDevice: nil)
        }.reversed()
        var requests = [[String: String]]()
        let history = MessageHistory { params in
            requests.append(params)
            let filtered = records.filter { message in
                params["before"].map { MessageHistory.cursor(message) < $0 } ?? true
            }
            let batch = Array(filtered.prefix(30))
            return Page(items: batch, page: 1, totalPages: 100, total: 3000,
                        hasMore: filtered.count > 30, nextCursor: batch.last.map(MessageHistory.cursor))
        }
        try await history.refresh()
        XCTAssertEqual(history.page.items.last?.id, "2971")
        XCTAssertTrue(history.hasOlder)
        history.atBottom = false
        history.positionID = "2971"
        try await history.loadOlder()
        XCTAssertEqual(history.page.items.last?.id, "2941")
        XCTAssertEqual(history.positionID, "2971")
        while history.hasOlder { try await history.loadOlder() }
        XCTAssertEqual(history.page.items.count, 3000)
        XCTAssertEqual(history.page.items.last?.id, "0001")
        XCTAssertEqual(Set(history.page.items.map(\.id)).count, 3000)
        XCTAssertEqual(requests.count, 100)
        try await history.loadOlder()
        XCTAssertEqual(requests.count, 100)
    }

    func testOlderCursorStallStopsAndAllowsManualRetry() async throws {
        var stalled = false
        let history = MessageHistory { _ in
            Page(items: [self.message(stalled ? 3 : 2)], page: 1, totalPages: 2, total: 2, hasMore: stalled)
        }
        history.page = Page(items: [message(3)], page: 1, totalPages: 2, total: 2)
        history.ready = true
        history.hasOlder = true
        stalled = true
        do { try await history.loadOlder(); XCTFail("Expected stalled cursor to fail") } catch {}
        XCTAssertNotNil(history.olderError)
        XCTAssertFalse(history.loadingOlder)
        XCTAssertEqual(history.page.items.map(\.id), ["003"])
        stalled = false
        try await history.loadOlder()
        XCTAssertNil(history.olderError)
        XCTAssertFalse(history.hasOlder)
        XCTAssertEqual(history.page.items.map(\.id), ["003", "002"])
    }

    func testScrollMemoryDoesNotInvalidateMessageContent() {
        let history = MessageHistory { _ in .empty }
        history.page = Page(items: (0..<3000).map(message), page: 1, totalPages: 100, total: 3000)
        withObservationTracking {
            _ = history.page
            _ = history.positionID
        } onChange: {
            XCTFail("Scrolling must not invalidate message content")
        }
        for index in 0..<3000 { history.positionID = String(index) }
        history.updateBottomDistance(150)
        history.updateBottomDistance(0)
        XCTAssertEqual(history.positionID, "2999", "Showing or hiding the button must not reset the reading anchor")
    }

    func testBottomButtonHysteresisAndBounce() {
        let history = MessageHistory { _ in .empty }
        for distance: CGFloat in [-90, 0, 48, 65, 96] {
            history.updateBottomDistance(distance)
            XCTAssertTrue(history.atBottom)
        }
        history.updateBottomDistance(97)
        XCTAssertFalse(history.atBottom)
        for distance: CGFloat in [96, 70, 49, .infinity, .nan] {
            history.updateBottomDistance(distance)
            XCTAssertFalse(history.atBottom)
        }
        history.updateBottomDistance(48)
        XCTAssertTrue(history.atBottom)
        withObservationTracking {
            _ = history.atBottom
        } onChange: {
            XCTFail("Bottom bounce must not keep notifying the UI")
        }
        for _ in 0..<100 { history.updateBottomDistance(-40); history.updateBottomDistance(0) }
    }

    func message(_ n: Int) -> Message {
        Message(id: String(format: "%03d", n), content: "消息 \(n)", createdAt: "2026-11-09T00:00:00.000Z", isStarred: false, senderDevice: nil)
    }
    func testHistorySurvivesCursorDeletionInsertionAndRefresh() async throws {
        var records = (0..<9).map(message)
        var failed = false
        var calls = [[String: String]]()
        let history = MessageHistory { params in
            calls.append(params)
            if failed { throw APIError(message: "offline") }
            let result = records.reversed().filter {
                (params["before"] == nil || MessageHistory.cursor($0) < params["before"]!) &&
                (params["since"] == nil || MessageHistory.cursor($0) >= params["since"]!)
            }
            let items = Array(result.prefix(3))
            return Page(items: items, page: 1, totalPages: 3, total: records.count,
                        hasMore: result.count > 3, nextCursor: result.count > 3 ? items.last.map(MessageHistory.cursor) : nil)
        }
        try await history.refresh()
        XCTAssertEqual(history.page.items.map(\.id), ["008", "007", "006"])
        failed = true
        do { try await history.loadOlder(); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(history.page.items.count, 3)
        XCTAssertNotNil(history.olderError)
        failed = false
        records.removeAll { $0.id == "006" }
        records.append(message(9))
        async let older: Void = history.loadOlder()
        async let refresh: Void = history.refresh()
        _ = try await (older, refresh)
        XCTAssertEqual(history.page.items.map(\.id), ["009", "008", "007", "005", "004", "003"])
        XCTAssertNil(history.olderError)
        try await history.loadOlder()
        XCTAssertFalse(history.hasOlder)
        XCTAssertEqual(Set(history.page.items.map(\.id)).count, 9)
        XCTAssertTrue(calls.contains { $0["since"] != nil && $0["before"] != nil })
        failed = true
        do { try await history.refresh(); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(history.page.items.count, 9)
    }
    func testConversationWindowsRetainHistoryAndReadingPosition() async {
        let api = MockAPI { _, _, _, _ in Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8) }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        model.selected = Conversation(id: "a", title: "A", preview: nil, messageCount: 0)
        let first = model.messageHistory
        first.positionID = "saved"; first.atBottom = false
        model.selected = Conversation(id: "b", title: "B", preview: nil, messageCount: 0)
        XCTAssertFalse(model.messageHistory === first)
        model.selected = Conversation(id: "a", title: "A", preview: nil, messageCount: 0)
        XCTAssertTrue(model.messageHistory === first)
        XCTAssertEqual(model.messageHistory.positionID, "saved")
        XCTAssertFalse(model.messageHistory.atBottom)
    }
}
