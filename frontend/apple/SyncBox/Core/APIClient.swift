import Foundation

protocol APITransport {
    func events() -> AsyncThrowingStream<SyncEvent, Error>
    func request(_ path: String, method: String, query: [String: String], body: Data?, contentType: String) async throws -> Data
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
        guard (1...5).contains(files.count), files.allSatisfy({ !$0.data.isEmpty }), files.reduce(0, { $0 + $1.data.count }) <= 20 * 1024 * 1024 else {
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
            body.append(file.data); append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return try JSONDecoder().decode(Message.self, from: await request("/conversations/\(conversationID)/attachments", method: "POST", query: [:], body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
    }
    func remove(_ path: String, method: String = "DELETE") async throws {
        _ = try await request(path, method: method, query: [:], body: nil)
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class APIClient: APITransport {
    let server: URL
    var token: String?
    private let session: URLSession
    init(server: URL, session: URLSession? = nil) {
        self.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

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
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["message"] as? String) ?? (json?["message"] as? [String])?.joined(separator: "；")
            throw APIError(message: message ?? "请求失败（\(http.statusCode)），请检查服务地址与反向代理", status: http.statusCode, code: json?["code"] as? String)
        }
        return data
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
