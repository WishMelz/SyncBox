import CryptoKit
import Foundation

protocol APITransport {
    func events() -> AsyncThrowingStream<SyncEvent, Error>
    func request(_ path: String, method: String, query: [String: String], body: Data?, contentType: String) async throws -> Data
    func sendFiles(
        _ conversationID: String,
        files: [PendingFile],
        content: String,
        clientId: String?,
        onProgress: (@MainActor @Sendable (UploadProgress) -> Void)?
    ) async throws -> Message
    func cancelCurrentUpload()
    func downloadBackup() async throws -> BackupPayload
    func imageData(_ messageID: String) async throws -> Data
    func attachmentData(_ messageID: String, attachmentID: String, preview: Bool) async throws -> Data
    func removeAttachment(_ messageID: String, attachmentID: String) async throws
    func removeImage(_ messageID: String) async throws
    func invalidateMessageMediaCache(_ messageID: String)
    func clearMediaCache()
}

extension APITransport {
    func events() -> AsyncThrowingStream<SyncEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
    func request(_ path: String, method: String, query: [String: String], body: Data?) async throws -> Data {
        try await request(path, method: method, query: query, body: body, contentType: "application/json")
    }
    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, method: "GET", query: query, body: nil))
    }
    func send<T: Decodable, B: Encodable>(_ path: String, method: String = "POST", body: B) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, method: method, query: [:], body: JSONEncoder().encode(body)))
    }
    func sendImage(_ conversationID: String, data: Data, content: String, clientId: String? = nil) async throws -> Message {
        let boundary = "SyncBox-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\n\(content)\r\n")
        if let clientId { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"clientId\"\r\n\r\n\(clientId)\r\n") }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"image\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return try JSONDecoder().decode(Message.self, from: await request("/conversations/\(conversationID)/images", method: "POST", query: [:], body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
    }

    func sendFiles(_ conversationID: String, files: [PendingFile], content: String, clientId: String? = nil) async throws -> Message {
        try await sendFiles(conversationID, files: files, content: content, clientId: clientId, onProgress: nil)
    }

    func sendFiles(
        _ conversationID: String,
        files: [PendingFile],
        content: String,
        clientId: String?,
        onProgress: (@MainActor @Sendable (UploadProgress) -> Void)?
    ) async throws -> Message {
        guard (1...5).contains(files.count), files.allSatisfy({ $0.size > 0 }), files.reduce(0, { $0 + $1.size }) <= 20 * 1024 * 1024 else {
            throw APIError(message: "最多 5 个非空文件，合计不超过 20 MB")
        }
        let boundary = "SyncBox-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        let names = String(decoding: try JSONEncoder().encode(files.map(\.name)), as: UTF8.self)
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\n\(content)\r\n")
        if let clientId { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"clientId\"\r\n\r\n\(clientId)\r\n") }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"names\"\r\n\r\n\(names)\r\n")
        for file in files {
            let multipartName = file.name
                .replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_")
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(multipartName)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
            if let fileURL = file.fileURL {
                body.append(try Data(contentsOf: fileURL))
            } else {
                body.append(file.data)
            }
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        if let onProgress {
            let total = Int64(body.count)
            await onProgress(UploadProgress(loaded: 0, total: total))
        }
        let message = try JSONDecoder().decode(
            Message.self,
            from: await request("/conversations/\(conversationID)/attachments", method: "POST", query: [:], body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        )
        if let onProgress {
            let total = Int64(body.count)
            await onProgress(UploadProgress(loaded: total, total: total))
        }
        return message
    }

    func cancelCurrentUpload() {}

    func downloadBackup() async throws -> BackupPayload {
        throw APIError(message: "当前传输层不支持备份下载")
    }

    func imageData(_ messageID: String) async throws -> Data {
        try await request("/messages/\(messageID)/image", method: "GET", query: [:], body: nil)
    }

    func attachmentData(_ messageID: String, attachmentID: String, preview: Bool) async throws -> Data {
        try await request("/messages/\(messageID)/attachments/\(attachmentID)" + (preview ? "/preview" : ""), method: "GET", query: [:], body: nil)
    }

    func invalidateMessageMediaCache(_ messageID: String) {}
    func clearMediaCache() {}

    func remove(_ path: String, method: String = "DELETE") async throws {
        _ = try await request(path, method: method, query: [:], body: nil)
    }

    func editMessage(_ messageID: String, content: String) async throws -> Message {
        try await send("/messages/\(messageID)", method: "PATCH", body: ["content": content])
    }

    func removeAttachment(_ messageID: String, attachmentID: String) async throws {
        try await remove("/messages/\(messageID)/attachments/\(attachmentID)")
        invalidateMessageMediaCache(messageID)
    }

    func removeImage(_ messageID: String) async throws {
        try await remove("/messages/\(messageID)/image")
        invalidateMessageMediaCache(messageID)
    }

    func messageDetail(_ messageID: String) async throws -> Message {
        try await get("/messages/\(messageID)")
    }

    func files(query: String = "", category: String? = nil, sort: String = "newest", page: Int = 1) async throws -> Page<FileItem> {
        var params: [String: String] = [
            "q": String(query.prefix(200)),
            "sort": sort,
            "page": String(page),
            "pageSize": "30"
        ]
        if let category, !category.isEmpty, category != "all" {
            params["category"] = category
        }
        return try await get("/messages/files", query: params)
    }

    func deleteFile(_ file: FileItem) async throws {
        if file.kind == "image" {
            try await removeImage(file.messageId)
        } else {
            try await removeAttachment(file.messageId, attachmentID: file.id)
        }
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let totalExpectedFallback: Int64
    let onProgress: (@MainActor @Sendable (UploadProgress) -> Void)?

    init(totalExpectedFallback: Int64, onProgress: (@MainActor @Sendable (UploadProgress) -> Void)?) {
        self.totalExpectedFallback = totalExpectedFallback
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let onProgress else { return }
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : totalExpectedFallback
        let progress = UploadProgress(loaded: min(totalBytesSent, total), total: total)
        Task { @MainActor in
            onProgress(progress)
        }
    }
}

final class APIClient: APITransport, @unchecked Sendable {
    let server: URL
    let mediaCache = MediaCache()
    var token: String? {
        didSet {
            if token != oldValue {
                mediaCache.clear()
            }
        }
    }
    private let session: URLSession
    private let uploadLock = NSLock()
    private var activeUploadTask: Task<(Data, URLResponse), Error>?

    init(server: URL, session: URLSession? = nil) {
        self.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit {
        mediaCache.clear()
        session.invalidateAndCancel()
    }

    static func normalizeServer(_ text: String, allowHTTP: Bool) throws -> URL {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw APIError(message: "请输入服务地址，例如 https://sync.example.com，不含 /api 路径")
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        if parts.scheme == "http" && !allowHTTP {
            throw APIError(message: "HTTP 不加密，请先确认仅在受信任的局域网使用")
        }
        parts.path = ""
        guard let url = parts.url else { throw APIError(message: "服务地址无效") }
        return url
    }

    private func decodeAPIError(data: Data, status: Int) -> APIError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (json?["message"] as? String) ?? (json?["message"] as? [String])?.joined(separator: "；")
        return APIError(message: message ?? "请求失败（\(status)），请检查服务地址与反向代理", status: status, code: json?["code"] as? String)
    }

    func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1" + path
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "服务响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            throw decodeAPIError(data: data, status: http.statusCode)
        }
        return data
    }

    func imageData(_ messageID: String) async throws -> Data {
        let path = "/messages/\(messageID)/image"
        return try await mediaCache.getOrFetch(server: server.absoluteString, token: token, path: path) { [self] in
            try await self.request(path, method: "GET", query: [:], body: nil)
        }
    }

    func attachmentData(_ messageID: String, attachmentID: String, preview: Bool) async throws -> Data {
        let path = "/messages/\(messageID)/attachments/\(attachmentID)" + (preview ? "/preview" : "")
        if preview {
            return try await mediaCache.getOrFetch(server: server.absoluteString, token: token, path: path) { [self] in
                try await self.request(path, method: "GET", query: [:], body: nil)
            }
        }
        return try await request(path, method: "GET", query: [:], body: nil)
    }

    func removeAttachment(_ messageID: String, attachmentID: String) async throws {
        try await remove("/messages/\(messageID)/attachments/\(attachmentID)")
        mediaCache.invalidatePath("/messages/\(messageID)/attachments/\(attachmentID)")
    }

    func removeImage(_ messageID: String) async throws {
        try await remove("/messages/\(messageID)/image")
        mediaCache.invalidatePath("/messages/\(messageID)/image")
    }

    func invalidateMessageMediaCache(_ messageID: String) {
        mediaCache.invalidateMessage(messageID)
    }

    func clearMediaCache() {
        mediaCache.clear()
    }

    func sendFiles(
        _ conversationID: String,
        files: [PendingFile],
        content: String,
        clientId: String?,
        onProgress: (@MainActor @Sendable (UploadProgress) -> Void)?
    ) async throws -> Message {
        guard (1...5).contains(files.count),
              files.allSatisfy({ $0.size > 0 }),
              files.reduce(0, { $0 + $1.size }) <= 20 * 1024 * 1024 else {
            throw APIError(message: "最多 5 个非空文件，合计不超过 20 MB")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncbox-upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let boundary = "SyncBox-\(UUID().uuidString)"
        guard FileManager.default.createFile(
            atPath: tempURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw APIError(message: "无法创建临时上传文件")
        }

        let handle = try FileHandle(forWritingTo: tempURL)
        do {
            func writeString(_ string: String) throws {
                try handle.write(contentsOf: Data(string.utf8))
            }
            let names = String(decoding: try JSONEncoder().encode(files.map(\.name)), as: UTF8.self)
            try writeString("--\(boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\n\(content)\r\n")
            if let clientId {
                try writeString("--\(boundary)\r\nContent-Disposition: form-data; name=\"clientId\"\r\n\r\n\(clientId)\r\n")
            }
            try writeString("--\(boundary)\r\nContent-Disposition: form-data; name=\"names\"\r\n\r\n\(names)\r\n")
            for file in files {
                let multipartName = file.name
                    .replacingOccurrences(of: "\"", with: "_")
                    .replacingOccurrences(of: "\r", with: "_")
                    .replacingOccurrences(of: "\n", with: "_")
                try writeString("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(multipartName)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
                if let fileURL = file.fileURL {
                    let reader = try FileHandle(forReadingFrom: fileURL)
                    defer { try? reader.close() }
                    while true {
                        var finished = false
                        try autoreleasepool {
                            let chunk = try reader.read(upToCount: 65_536)
                            if let chunk, !chunk.isEmpty {
                                try handle.write(contentsOf: chunk)
                            } else {
                                finished = true
                            }
                        }
                        if finished { break }
                    }
                } else {
                    try handle.write(contentsOf: file.data)
                }
                try writeString("\r\n")
            }
            try writeString("--\(boundary)--\r\n")
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        let fileSize = try tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let totalExpected = Int64(fileSize)

        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/conversations/\(conversationID)/attachments"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(totalExpected), forHTTPHeaderField: "Content-Length")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        if let onProgress {
            await onProgress(UploadProgress(loaded: 0, total: totalExpected))
        }

        let uploadRequest = request
        let delegate = UploadProgressDelegate(totalExpectedFallback: totalExpected, onProgress: onProgress)
        let task = Task<(Data, URLResponse), Error> {
            try await self.session.upload(for: uploadRequest, fromFile: tempURL, delegate: delegate)
        }
        uploadLock.withLock { activeUploadTask = task }
        defer {
            uploadLock.withLock {
                activeUploadTask = nil
            }
        }

        let (data, response) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        guard let http = response as? HTTPURLResponse else { throw APIError(message: "服务响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            throw decodeAPIError(data: data, status: http.statusCode)
        }
        if let onProgress {
            await onProgress(UploadProgress(loaded: totalExpected, total: totalExpected))
        }
        return try JSONDecoder().decode(Message.self, from: data)
    }

    func cancelCurrentUpload() {
        uploadLock.withLock {
            activeUploadTask?.cancel()
        }
    }

    func downloadBackup() async throws -> BackupPayload {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/settings/backup"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.setValue("application/x-sqlite3", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "服务响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            throw decodeAPIError(data: data, status: http.statusCode)
        }

        guard let expected = http.value(forHTTPHeaderField: "X-SyncBox-Backup-SHA256")?.lowercased(),
              !expected.isEmpty else {
            throw APIError(message: "备份缺少完整性校验信息，未保存文件")
        }

        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw APIError(message: "备份校验失败，未保存文件")
        }

        var filename = "syncbox-backup.sqlite"
        if let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
            let match = String(disposition[range])
            filename = String(match.dropFirst("filename=\"".count).dropLast())
        }

        return BackupPayload(data: data, sha256: actual, filename: filename, size: data.count)
    }

    func events() -> AsyncThrowingStream<SyncEvent, Error> {
        let configuration = session.configuration
        configuration.timeoutIntervalForRequest = 60 // Server heartbeats arrive every 20 seconds.
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let streamSession = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/events"
        var request = URLRequest(url: components.url!)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let task = Task {
                defer { streamSession.invalidateAndCancel() }
                do {
                    let (bytes, response) = try await streamSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError(message: "服务响应无效") }
                    guard http.statusCode == 200 else { throw APIError(message: "实时同步连接失败", status: http.statusCode) }
                    guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
                        throw APIError(message: "服务未提供实时同步")
                    }
                    continuation.yield(.init(type: "connected", scope: "all", conversationId: nil, messageId: nil, at: nil))
                    var parser = SyncEventParser()
                    // Read bytes to preserve empty SSE frame separators, including CRLF.
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let event = try parser.add(byte) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled { continuation.finish() }
                    else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                streamSession.invalidateAndCancel()
            }
        }
    }
}
