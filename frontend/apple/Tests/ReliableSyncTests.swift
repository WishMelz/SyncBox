import XCTest
@testable import SyncBoxCore

final class StreamingURLProtocol: URLProtocol {
    static var status = 200
    static var stopped: (() -> Void)?
    static var requested: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requested?(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        if Self.status != 200 { client?.urlProtocolDidFinishLoading(self); return }
        let payload = Array("retry: 3000\n\n: heartbeat\n\nevent: sync\ndata: {\"type\":\"invalidate\",\"scope\":\"messages\",\"conversationId\":\"中文\"}\n\n".utf8)
        for byte in payload { client?.urlProtocol(self, didLoad: Data([byte])) }
        // Keep the connection open until the consumer cancels it.
    }
    override func stopLoading() { Self.stopped?() }
}

final class BackupAndUploadURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class ReliableSyncTests: XCTestCase {
    func testSSEUsesProtocolDispatchPreservesUTF8AndCancelsImmediately() async {
        let received = expectation(description: "event")
        let stopped = expectation(description: "closed")
        StreamingURLProtocol.status = 200
        StreamingURLProtocol.stopped = { stopped.fulfill() }
        StreamingURLProtocol.requested = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/events")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingURLProtocol.self]
        let client = APIClient(server: URL(string: "https://sync.example")!, session: URLSession(configuration: config))
        client.token = "token"
        let transport: APITransport = client
        let listener = Task {
            do {
                for try await event in transport.events() {
                    if event.type == "invalidate" {
                        XCTAssertEqual(event.conversationId, "中文")
                        received.fulfill()
                    }
                }
            } catch { if !Task.isCancelled { XCTFail("\(error)") } }
        }
        await fulfillment(of: [received], timeout: 3)
        listener.cancel()
        await listener.value
        await fulfillment(of: [stopped], timeout: 3)
        StreamingURLProtocol.stopped = nil
        StreamingURLProtocol.requested = nil
    }

    func testSSEUnauthorizedStatusReachesCaller() async {
        StreamingURLProtocol.status = 401
        defer { StreamingURLProtocol.status = 200 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingURLProtocol.self]
        let transport: APITransport = APIClient(server: URL(string: "https://sync.example")!, session: URLSession(configuration: config))
        do {
            for try await _ in transport.events() { XCTFail("401 must not emit events") }
            XCTFail("401 must throw")
        } catch { XCTAssertEqual((error as? APIError)?.status, 401) }
    }

    func testParserSupportsCRLFMultilineAndMultipleFrames() throws {
        var parser = SyncEventParser()
        let payload = ": ping\r\n\r\nevent: sync\r\ndata: {\"type\":\"invalidate\",\r\ndata: \"scope\":\"messages\"}\r\n\r\ndata: {\"type\":\"invalidate\",\"scope\":\"favorites\"}\n\n"
        var scopes: [String] = []
        for byte in payload.utf8 { if let event = try parser.add(byte) { scopes.append(event.scope) } }
        XCTAssertEqual(scopes, ["messages", "favorites"])
    }

    func testTextImageAndFileRetryReuseIDUntilDraftChangesOrSendSucceeds() async {
        for kind in ["text", "image", "files"] {
            var sentIDs: [String] = []
            var fail = true
            let api = MockAPI { _, method, _, body in
                if method == "POST" {
                    let data = body!
                    if kind == "text" {
                        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
                        sentIDs.append(json["clientId"]!)
                    } else {
                        let text = String(decoding: data, as: UTF8.self)
                        let id = text.components(separatedBy: "name=\"clientId\"\r\n\r\n")[1].components(separatedBy: "\r\n")[0]
                        sentIDs.append(id)
                    }
                    if fail { throw URLError(.timedOut) }
                    return Data("{\"id\":\"m\",\"content\":\"sent\",\"createdAt\":\"now\",\"isStarred\":false}".utf8)
                }
                return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
            }
            let model = WorkspaceModel(api: api, onUnauthorized: {})
            model.selected = .init(id: "one", title: "One", preview: nil, messageCount: 0)
            model.draft = "original"
            if kind == "image" { model.imageDrafts["one"] = Data([1, 2, 3]) }
            if kind == "files" { model.fileDrafts["one"] = [.init(name: "one.txt", data: Data([1, 2, 3]))] }
            await model.send()
            await model.send()
            XCTAssertEqual(sentIDs.count, 2)
            XCTAssertEqual(sentIDs[0], sentIDs[1], kind)
            XCTAssertNotNil(UUID(uuidString: sentIDs[0]))
            XCTAssertEqual(model.draft, "original")
            model.draft = "edited"
            fail = false
            await model.send()
            XCTAssertNotEqual(sentIDs[1], sentIDs[2], kind)
            model.draft = "edited"
            if kind == "image" { model.imageDrafts["one"] = Data([1, 2, 3]) }
            if kind == "files" { model.fileDrafts["one"] = [.init(name: "one.txt", data: Data([1, 2, 3]))] }
            await model.send()
            XCTAssertNotEqual(sentIDs[2], sentIDs[3], kind)
        }
    }

    func testNewUnreadMessagesAreMarkedReadDuringRefresh() async {
        var marked = 0
        let api = MockAPI { path, method, _, _ in
            if method == "PATCH" { marked += 1; return Data() }
            if path.hasSuffix("/messages") {
                return Data("{\"items\":[{\"id\":\"new\",\"content\":\"hi\",\"createdAt\":\"now\",\"isStarred\":false,\"isRead\":false}],\"page\":1,\"totalPages\":1,\"total\":1}".utf8)
            }
            return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
        }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        model.selected = .init(id: "one", title: "One", preview: nil, messageCount: 0)
        await model.refresh()
        XCTAssertEqual(marked, 1)
        model.messageQuery = "search"
        await model.loadMessages()
        XCTAssertEqual(marked, 1, "Searching must not clear the whole conversation")
    }
    func testSuccessfulSendWithFailedRefreshDoesNotBecomeFailedSend() async {
        for failedPath in ["/conversations", "/conversations/one/messages"] {
            var sends = 0
            let api = MockAPI { path, method, _, _ in
                if method == "POST" {
                    sends += 1
                    return Data("{\"id\":\"m\",\"content\":\"sent\",\"createdAt\":\"now\",\"isStarred\":false}".utf8)
                }
                if path == failedPath { throw APIError(message: "offline", status: 503) }
                return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
            }
            let model = WorkspaceModel(api: api, onUnauthorized: {})
            model.selected = .init(id: "one", title: "One", preview: nil, messageCount: 0)
            model.draft = "sent"
            await model.send()
            XCTAssertEqual(model.draft, "")
            XCTAssertEqual(model.error, "消息已发送，列表刷新失败，请刷新查看。")
            await model.refresh()
            XCTAssertEqual(sends, 1, "Refreshing must never resend a delivered message")
        }
    }

    func testFailedSendStaysInDraftAndRefreshNeverRetriesIt() async {
        var sends = 0
        let api = MockAPI { _, method, _, _ in
            if method == "POST" { sends += 1; throw APIError(message: "发送失败", status: 503) }
            return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
        }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        model.selected = .init(id: "one", title: "One", preview: nil, messageCount: 0)
        model.draft = "keep"
        await model.send()
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(model.draft, "keep")
        XCTAssertEqual(sends, 1)
        await model.send()
        XCTAssertEqual(sends, 2, "Only an explicit send retries the draft")
    }

    func testScopedEventRoutingAvoidsUnrelatedHistoryAndPatchesSelectedMessage() async throws {
        final class ScopedEventTransport: APITransport {
            var continuation: AsyncThrowingStream<SyncEvent, Error>.Continuation?
            var recorded: [String] = []
            var messageContent = "initial"
            var deleted = false

            func events() -> AsyncThrowingStream<SyncEvent, Error> {
                AsyncThrowingStream { cont in
                    self.continuation = cont
                    cont.yield(.init(type: "connected", scope: "all", conversationId: nil, messageId: nil, at: nil))
                }
            }

            func request(_ path: String, method: String, query: [String: String], body: Data?, contentType: String) async throws -> Data {
                recorded.append("\(method) \(path)")
                if path == "/conversations" {
                    return Data("{\"items\":[{\"id\":\"one\",\"title\":\"One\"}],\"page\":1,\"totalPages\":1,\"total\":1}".utf8)
                }
                if path == "/conversations/one/messages" {
                    let payload = deleted
                        ? "{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}"
                        : "{\"items\":[{\"id\":\"m1\",\"conversationId\":\"one\",\"content\":\"\(messageContent)\",\"createdAt\":\"2026-11-09T00:00:00.000Z\",\"isStarred\":false}],\"page\":1,\"totalPages\":1,\"total\":1}"
                    return Data(payload.utf8)
                }
                if path == "/messages/m1" {
                    if deleted { throw APIError(message: "not found", status: 404) }
                    return Data("{\"id\":\"m1\",\"conversationId\":\"one\",\"content\":\"\(messageContent)\",\"createdAt\":\"2026-11-09T00:00:00.000Z\",\"isStarred\":false}".utf8)
                }
                return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
            }
        }

        let transport = ScopedEventTransport()
        let model = WorkspaceModel(api: transport, onUnauthorized: {})
        model.selected = .init(id: "one", title: "One", preview: nil, messageCount: 1)
        await model.loadMessages(reconcile: true)
        model.startEvents()
        try await Task.sleep(for: .milliseconds(250))
        defer { model.stopEvents() }
        transport.recorded.removeAll()

        // Unrelated conversation message invalidation triggers 0 requests.
        transport.continuation?.yield(.init(type: "invalidate", scope: "messages", conversationId: "two", messageId: "m2", at: nil))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(transport.recorded.isEmpty)

        // Selected conversation messageId invalidation fetches only /messages/m1.
        transport.messageContent = "patched"
        transport.continuation?.yield(.init(type: "invalidate", scope: "messages", conversationId: "one", messageId: "m1", at: nil))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(transport.recorded, ["GET /messages/m1"])
        XCTAssertEqual(model.messages.items.first?.content, "patched")
        transport.recorded.removeAll()

        // 404 on /messages/m1 removes the message locally.
        transport.deleted = true
        transport.continuation?.yield(.init(type: "invalidate", scope: "messages", conversationId: "one", messageId: "m1", at: nil))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(transport.recorded, ["GET /messages/m1"])
        XCTAssertTrue(model.messages.items.isEmpty)
    }

    func testFineGrainedMessageMutationLockDoesNotBlockOtherMessages() async throws {
        var gate: CheckedContinuation<Data, Error>?
        let api = MockAPI { _, method, _, _ in
            if method == "PATCH" {
                return try await withCheckedThrowingContinuation { gate = $0 }
            }
            return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
        }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        let m1 = Message(id: "m1", content: "one", createdAt: "2026-11-09T00:00:00.000Z", isStarred: false, senderDevice: nil)
        let editTask = Task {
            try await model.editMessage(m1, content: "edited")
        }
        while gate == nil { await Task.yield() }
        XCTAssertTrue(model.isMutatingMessage("m1"))
        XCTAssertFalse(model.isMutatingMessage("m2"))
        XCTAssertTrue(model.mutating)

        gate?.resume(returning: Data("{\"id\":\"m1\",\"content\":\"edited\",\"createdAt\":\"2026-11-09T00:00:00.000Z\",\"isStarred\":false}".utf8))
        try await editTask.value
        XCTAssertFalse(model.isMutatingMessage("m1"))
        XCTAssertFalse(model.mutating)
    }

    func testDownloadBackupVerifiesSHA256AndProgressUploadStreamsFile() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackupAndUploadURLProtocol.self]
        let api = APIClient(server: URL(string: "https://sync.example")!, session: URLSession(configuration: config))
        api.token = "tok"

        let expectedDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        var sendHeader = expectedDigest
        BackupAndUploadURLProtocol.handler = { _ in
            (
                200,
                [
                    "Content-Type": "application/x-sqlite3",
                    "Content-Disposition": "attachment; filename=\"syncbox-ok.sqlite\"",
                    "X-SyncBox-Backup-SHA256": sendHeader
                ],
                Data("abc".utf8)
            )
        }
        let backup = try await api.downloadBackup()
        XCTAssertEqual(backup.filename, "syncbox-ok.sqlite")
        XCTAssertEqual(backup.sha256, expectedDigest)
        XCTAssertEqual(backup.size, 3)

        sendHeader = "0000"
        do {
            _ = try await api.downloadBackup()
            XCTFail("Mismatched backup digest must fail")
        } catch let err as APIError {
            XCTAssertTrue(err.message.contains("校验"))
        }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("syncbox-test-\(UUID().uuidString).txt")
        try Data("hello file".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        BackupAndUploadURLProtocol.handler = { _ in
            (201, ["Content-Type": "application/json"], Data("{\"id\":\"m9\",\"content\":\"\",\"createdAt\":\"2026-11-09T00:00:00.000Z\",\"isStarred\":false}".utf8))
        }
        @MainActor final class ProgressBox { var items: [UploadProgress] = [] }
        let seenProgress = ProgressBox()
        let uploaded = try await api.sendFiles(
            "conv-1",
            files: [PendingFile(name: "test.txt", size: 10, fileURL: tempFile, ownsFile: false)],
            content: "",
            clientId: "cid-1"
        ) { progress in
            seenProgress.items.append(progress)
        }
        XCTAssertEqual(uploaded.id, "m9")
        XCTAssertEqual(seenProgress.items.first?.loaded, 0)
        XCTAssertEqual(seenProgress.items.last?.percent, 100)
    }

}
