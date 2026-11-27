import Foundation
import Observation

/// One in-memory reading window. Requests are serialized so polling cannot
/// replace older messages while an upward load is still running.
@MainActor @Observable
final class MessageHistory {
    var page: Page<Message> = .empty
    var total = 0
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

    private func resolvedTotal(for items: [Message], result: Page<Message>) -> Int {
        if result.hasTotal {
            return max(result.total, items.count)
        }
        return max(total, items.count)
    }

    private func resolvedTotalPages(total: Int, result: Page<Message>) -> Int {
        if result.totalPages > 0 || total == 0 {
            return result.totalPages
        }
        return (total + 29) / 30
    }

    func reconcile() async throws {
        try await refresh()
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
                params["includeTotal"] = "false"
                result = try await fetch(params)
                items = Self.merge(items, result.items)
            }
            if items.isEmpty && result.total > 0 && since != nil {
                result = try await fetch([:]); items = result.items
            }
            // Commit only when the whole loaded range has refreshed successfully.
            let merged = Self.merge(items)
            let nextTotal = result.hasTotal ? max(result.total, merged.count) : max(total, merged.count)
            let nextTotalPages = resolvedTotalPages(total: nextTotal, result: result)
            total = nextTotal
            page = Page(items: merged, page: 1, totalPages: nextTotalPages, total: nextTotal)
            hasOlder = nextTotal > merged.count
            ready = true
        }
    }

    func refreshLatest() async throws {
        try await enqueue { [self] in
            if !ready {
                let result = try await fetch([:])
                let merged = Self.merge(result.items)
                let nextTotal = result.hasTotal ? max(result.total, merged.count) : merged.count
                let nextTotalPages = resolvedTotalPages(total: nextTotal, result: result)
                total = nextTotal
                page = Page(items: merged, page: 1, totalPages: nextTotalPages, total: nextTotal)
                hasOlder = nextTotal > merged.count
                ready = true
                return
            }
            let result = try await fetch([:])
            let merged: [Message]
            if result.hasMore != true || result.items.isEmpty {
                merged = Self.merge(result.items)
            } else if let tail = result.items.last {
                let boundary = Self.cursor(tail)
                let olderKept = page.items.filter { Self.cursor($0) < boundary }
                merged = Self.merge(result.items, olderKept)
            } else {
                merged = Self.merge(result.items)
            }
            let nextTotal = result.hasTotal ? max(result.total, merged.count) : max(total, merged.count)
            let nextTotalPages = resolvedTotalPages(total: nextTotal, result: result)
            total = nextTotal
            page = Page(items: merged, page: 1, totalPages: nextTotalPages, total: nextTotal)
            hasOlder = nextTotal > merged.count
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
                let result = try await fetch([
                    "before": Self.cursor(oldest),
                    "includeTotal": "false"
                ])
                if result.hasMore == true,
                   !result.items.contains(where: { Self.cursor($0) < Self.cursor(oldest) }) {
                    throw APIError(message: "历史消息加载位置未前进，请重试。")
                }
                let items = Self.merge(page.items, result.items)
                let nextTotal = resolvedTotal(for: items, result: result)
                let nextTotalPages = resolvedTotalPages(total: nextTotal, result: result)
                total = nextTotal
                page = Page(items: items, page: 1, totalPages: nextTotalPages, total: nextTotal)
                hasOlder = result.hasMore ?? (nextTotal > items.count)
            }
        } catch { olderError = "加载历史消息失败"; throw error }
    }

    func upsertMessage(_ message: Message) {
        let existed = page.items.contains(where: { $0.id == message.id })
        let items = Self.merge(page.items, [message])
        if !existed {
            total = max(total + 1, items.count)
        } else {
            total = max(total, items.count)
        }
        let nextTotalPages = total == 0 ? 0 : (total + 29) / 30
        page = Page(items: items, page: 1, totalPages: nextTotalPages, total: total)
        hasOlder = total > items.count
    }

    func removeMessage(_ id: String) {
        guard page.items.contains(where: { $0.id == id }) else { return }
        let items = page.items.filter { $0.id != id }
        total = max(total - 1, items.count)
        let nextTotalPages = total == 0 ? 0 : (total + 29) / 30
        page = Page(items: items, page: 1, totalPages: nextTotalPages, total: total)
        hasOlder = total > items.count
    }
}
