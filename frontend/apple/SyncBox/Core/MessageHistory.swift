import Foundation
import Observation

/// One in-memory reading window. Requests are serialized so polling cannot
/// replace older messages while an upward load is still running.
@MainActor @Observable
final class MessageHistory {
    var page: Page<Message> = .empty
    var ready = false
    var hasOlder = false
    var loadingOlder = false
    var olderError: String?
    // Scroll position is reading memory, not rendered data. Keep the binding's
    // value intact without invalidating the lazy message list on every gesture.
    @ObservationIgnored var positionID: String?
    var atBottom = true
    private var tail: Task<Void, Never>?
    private let fetch: ([String: String]) async throws -> Page<Message>

    init(fetch: @escaping ([String: String]) async throws -> Page<Message>) { self.fetch = fetch }
    func updateBottomDistance(_ distance: CGFloat) {
        guard distance.isFinite else { return }
        // Hysteresis prevents the button flickering near the boundary, including
        // changes in estimated row heights and the scroll view's bottom bounce.
        let next = distance <= (atBottom ? 96 : 48)
        if next != atBottom { atBottom = next }
    }
    static func cursor(_ message: Message) -> String { message.createdAt + "|" + message.id }
    static func merge(_ groups: [Message]...) -> [Message] {
        var unique: [String: Message] = [:]
        for group in groups { for message in group { unique[message.id] = message } }
        return unique.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }
    }
    private func enqueue(_ work: @escaping () async throws -> Void) async throws {
        let previous = tail
        let task = Task { await previous?.value; try await work() }
        tail = Task { _ = try? await task.value }
        try await task.value
    }
    func refresh() async throws {
        try await enqueue { [self] in
            let since = page.items.last.map(Self.cursor)
            var params = since.map { ["since": $0] } ?? [:]
            var result = try await fetch(params)
            var items = result.items
            var seen = Set<String>()
            while since != nil, result.hasMore == true, let cursor = result.nextCursor {
                guard seen.insert(cursor).inserted else { throw APIError(message: "历史消息加载位置未前进，请重试。") }
                params["before"] = cursor
                result = try await fetch(params)
                items = Self.merge(items, result.items)
            }
            if items.isEmpty && result.total > 0 && since != nil {
                result = try await fetch([:]); items = result.items
            }
            // Commit only when the whole loaded range has refreshed successfully.
            page = Page(items: Self.merge(items), page: 1, totalPages: result.totalPages, total: result.total)
            hasOlder = result.total > page.items.count
            ready = true
        }
    }
    func loadOlder() async throws {
        guard ready, hasOlder, !loadingOlder else { return }
        loadingOlder = true; olderError = nil
        defer { loadingOlder = false }
        do {
            try await enqueue { [self] in
                guard let oldest = page.items.last else { return }
                let result = try await fetch(["before": Self.cursor(oldest)])
                if result.hasMore == true,
                   !result.items.contains(where: { Self.cursor($0) < Self.cursor(oldest) }) {
                    throw APIError(message: "历史消息加载位置未前进，请重试。")
                }
                let items = Self.merge(page.items, result.items)
                page = Page(items: items, page: 1, totalPages: result.totalPages, total: result.total)
                hasOlder = result.hasMore ?? (result.total > items.count)
            }
        } catch { olderError = "加载历史消息失败"; throw error }
    }
}
