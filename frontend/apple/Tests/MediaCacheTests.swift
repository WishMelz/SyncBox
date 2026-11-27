import XCTest
@testable import SyncBoxCore

final class MediaCacheTests: XCTestCase {
    func testCostLimitEvictsAndIsolatesByServerAndToken() async throws {
        let cache = MediaCache(maxBytes: 10)
        var fetches = 0

        let first = try await cache.getOrFetch(
            server: "https://a.example.com",
            token: "tok-1",
            path: "/messages/m1/image"
        ) {
            fetches += 1
            return Data([1, 2, 3, 4, 5, 6])
        }
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(fetches, 1)

        // Same server + token + path hits cache.
        _ = try await cache.getOrFetch(
            server: "https://a.example.com",
            token: "tok-1",
            path: "/messages/m1/image"
        ) {
            fetches += 1
            return Data([9])
        }
        XCTAssertEqual(fetches, 1)

        // Different token or server must not reuse cached entry.
        _ = try await cache.getOrFetch(
            server: "https://a.example.com",
            token: "tok-2",
            path: "/messages/m1/image"
        ) {
            fetches += 1
            return Data([1, 2])
        }
        XCTAssertEqual(fetches, 2)

        _ = try await cache.getOrFetch(
            server: "https://b.example.com",
            token: "tok-1",
            path: "/messages/m1/image"
        ) {
            fetches += 1
            return Data([3, 4])
        }
        XCTAssertEqual(fetches, 3)

        // Invalidate message evicts all server/token variants for that message.
        cache.invalidateMessage("m1")
        XCTAssertNil(cache.cachedData(server: "https://a.example.com", token: "tok-1", path: "/messages/m1/image"))
        XCTAssertNil(cache.cachedData(server: "https://b.example.com", token: "tok-1", path: "/messages/m1/image"))
    }

    func testDeduplicatesConcurrentFetchesAndClears() async throws {
        let cache = MediaCache()
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()

        async let a = cache.getOrFetch(server: "https://sync.example", token: "t", path: "/messages/m2/image") {
            counter.value += 1
            try await Task.sleep(for: .milliseconds(30))
            return Data([7, 8, 9])
        }
        async let b = cache.getOrFetch(server: "https://sync.example", token: "t", path: "/messages/m2/image") {
            counter.value += 1
            try await Task.sleep(for: .milliseconds(30))
            return Data([7, 8, 9])
        }

        let results = try await (a, b)
        XCTAssertEqual(results.0, Data([7, 8, 9]))
        XCTAssertEqual(results.1, Data([7, 8, 9]))
        XCTAssertEqual(counter.value, 1)

        cache.clear()
        XCTAssertNil(cache.cachedData(server: "https://sync.example", token: "t", path: "/messages/m2/image"))
    }
}
