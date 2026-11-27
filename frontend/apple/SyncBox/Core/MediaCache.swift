import Foundation

/// In-memory byte-bounded cache for decrypted image and attachment preview bytes.
/// Uses NSCache so the OS can also reclaim entries under memory pressure, and never writes to disk.
final class MediaCache: @unchecked Sendable {
    static let defaultMaxBytes = 50 * 1024 * 1024

    let maxBytes: Int
    private let cache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var keys: Set<String> = []
    private var inFlight: [String: Task<Data, Error>] = [:]
    private let evictDelegate = EvictionDelegate()

    private final class EvictionDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
        var onEvict: (@Sendable () -> Void)?
        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
            onEvict?()
        }
    }

    init(maxBytes: Int = MediaCache.defaultMaxBytes) {
        self.maxBytes = maxBytes
        self.cache.totalCostLimit = maxBytes
        self.evictDelegate.onEvict = nil
        self.cache.delegate = self.evictDelegate
    }

    static func cacheKey(server: String, token: String?, path: String) -> String {
        "\(server)|\(token ?? "")|\(path)"
    }

    func cachedData(server: String, token: String?, path: String) -> Data? {
        let key = Self.cacheKey(server: server, token: token, path: path) as NSString
        return cache.object(forKey: key) as Data?
    }

    func getOrFetch(
        server: String,
        token: String?,
        path: String,
        fetch: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let key = Self.cacheKey(server: server, token: token, path: path)
        if let hit = cache.object(forKey: key as NSString) {
            return hit as Data
        }

        let task: Task<Data, Error> = lock.withLock {
            if let existing = inFlight[key] {
                return existing
            }
            let created = Task<Data, Error> {
                try await fetch()
            }
            inFlight[key] = created
            return created
        }

        do {
            let data = try await task.value
            lock.withLock {
                _ = inFlight.removeValue(forKey: key)
                if data.count <= maxBytes {
                    cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
                    keys.insert(key)
                }
            }
            return data
        } catch {
            _ = lock.withLock {
                inFlight.removeValue(forKey: key)
            }
            throw error
        }
    }

    func invalidateMessage(_ messageID: String) {
        invalidatePath("/messages/\(messageID)")
    }

    func invalidatePath(_ pathPrefix: String) {
        let matches: [String] = lock.withLock {
            let selected = keys.filter { key in
                guard let idx = key.lastIndex(of: "|") else { return false }
                let path = String(key[key.index(after: idx)...])
                return path.hasPrefix(pathPrefix)
            }
            for key in selected {
                keys.remove(key)
                cache.removeObject(forKey: key as NSString)
            }
            return selected
        }
        _ = matches
    }

    func clear() {
        lock.withLock {
            cache.removeAllObjects()
            keys.removeAll()
            for task in inFlight.values {
                task.cancel()
            }
            inFlight.removeAll()
        }
    }
}
