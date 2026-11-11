import XCTest
@testable import SyncBoxCore

@MainActor
final class MessageHistoryTests: XCTestCase {
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
