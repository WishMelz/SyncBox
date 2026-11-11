import XCTest
@testable import SyncBoxCore

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MemoryStore: SessionStore {
    var value: SavedConnection?
    let identity = UUID().uuidString.lowercased()
    func installationId() throws -> String { identity }
    func read() throws -> SavedConnection? { value }
    func save(_ value: SavedConnection) throws { self.value = value }
}
final class MockAPI: APITransport {
    var handler: (String, String, [String: String], Data?) async throws -> Data
    init(_ handler: @escaping (String, String, [String: String], Data?) async throws -> Data) { self.handler = handler }
    func request(_ path: String, method: String, query: [String: String], body: Data?, contentType: String) async throws -> Data {
        try await handler(path, method, query, body)
    }
}

@MainActor
final class SyncBoxCoreTests: XCTestCase {
    func client(_ url: URL = URL(string: "https://sync.example.com")!) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(server: url, session: URLSession(configuration: configuration))
    }
    func connection(_ store: MemoryStore) -> ConnectionModel {
        ConnectionModel(platform: "macos", deviceName: "Test Mac", store: store, factory: { [self] in client($0) })
    }
    func conversation(_ id: String) -> Conversation { .init(id: id, title: id, preview: nil, messageCount: 0) }
    func messagePage(_ id: String) -> Data {
        Data("{\"items\":[{\"id\":\"\(id)\",\"content\":\"内容\",\"createdAt\":\"2026-11-07T00:00:00.000Z\",\"isStarred\":false}],\"page\":1,\"totalPages\":1,\"total\":1}".utf8)
    }
    func testServerValidationAndHTTPConsent() throws {
        XCTAssertEqual(try APIClient.normalizeServer(" https://Sync.Example.com/ ", allowHTTP: false).absoluteString, "https://sync.example.com")
        for invalid in ["file:///tmp", "https://user:pass@example.com", "https://example.com/api", "https://example.com?token=x", "https://example.com#x", "http://127.0.0.1:3000"] {
            XCTAssertThrowsError(try APIClient.normalizeServer(invalid, allowHTTP: false), invalid)
        }
        XCTAssertEqual(try APIClient.normalizeServer("http://192.168.1.2:3000", allowHTTP: true).port, 3000)
    }
    func testRequestEncodingAuthAndValidationError() async throws {
        let api = client()
        api.token = "test-token"
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.url?.path, "/api/v1/conversations")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "中文 & %_?")
            return (400, "{\"message\":[\"first\",\"second\"]}")
        }
        do {
            _ = try await api.request("/conversations", query: ["q": "中文 & %_?"])
            XCTFail("Must fail")
        } catch let error as APIError { XCTAssertEqual(error.status, 400); XCTAssertEqual(error.message, "first；second") }
        catch { XCTFail("Unexpected \(error)") }
    }
    func testSetupPersistsSessionAndRestartResumesThenLogoutClearsToken() async {
        let store = MemoryStore()
        // Use an isolated connection to make storage assertions explicit.
        let subject = connection(store)
        var paths: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            switch request.url!.path {
            case "/api/v1/auth/status": return (200, "{\"initialized\":false}")
            case "/api/v1/auth/setup": return (201, "{\"accessToken\":\"secret\",\"user\":{\"username\":\"theo\"}}")
            case "/api/v1/devices":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                return (201, "{\"id\":\"device-1\",\"name\":\"Test Mac\",\"platform\":\"macos\",\"lastSeenAt\":\"now\"}")
            case "/api/v1/auth/me": return (200, "{\"username\":\"theo\",\"deviceId\":\"device-1\"}")
            case "/api/v1/auth/logout": return (204, "")
            default: XCTFail("Unexpected request"); return (500, "{}")
            }
        }
        subject.serverText = "https://sync.example.com"
        await subject.connect()
        XCTAssertFalse(subject.initialized)
        subject.username = "theo"
        await subject.authenticate(password: "123456")
        XCTAssertEqual(subject.stage, .workspace)
        XCTAssertEqual(subject.api?.token, "secret")
        let restarted = connection(store)
        await restarted.restore()
        XCTAssertEqual(restarted.stage, .workspace)
        XCTAssertEqual(restarted.api?.token, "secret")
        XCTAssertEqual(restarted.username, "theo")
        XCTAssertTrue(paths.contains("/api/v1/auth/me"))
        XCTAssertEqual(store.value?.deviceId, "device-1")
        await subject.logout()
        XCTAssertEqual(subject.stage, .credentials)
        XCTAssertNil(subject.api?.token)
        XCTAssertNil(store.value?.token)
        XCTAssertEqual(subject.username, "")
        XCTAssertTrue(paths.contains("/api/v1/auth/setup"))
    }
    func testSetupConflictSwitchesToLoginAndShortPasswordNeverSent() async {
        let model = connection(MemoryStore())
        StubURLProtocol.handler = { request in
            request.url!.path.hasSuffix("status") ? (200, "{\"initialized\":false}") : (409, "{\"message\":\"already initialized\"}")
        }
        model.serverText = "https://sync.example.com"
        await model.connect()
        model.username = "theo"
        await model.authenticate(password: "12345")
        XCTAssertFalse(model.initialized)
        XCTAssertNotNil(model.error)
        await model.authenticate(password: "123456")
        XCTAssertTrue(model.initialized)
        XCTAssertEqual(model.stage, .credentials)
    }
    func testRestoreOnlyChecksStatusAndServerSwitchDoesNotForwardCredentials() async {
        let store = MemoryStore()
        store.value = .init(server: "https://old.example.com", allowHTTP: false, deviceId: "old-device", deviceName: "Mac")
        let model = connection(store)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url!.path, "/api/v1/auth/status")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url!.host == "new.example.com" { XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")) }
            return (200, "{\"initialized\":true}")
        }
        await model.restore()
        XCTAssertEqual(model.stage, .credentials)
        XCTAssertNil(model.api?.token)
        model.editServer()
        model.serverText = "https://new.example.com"
        await model.connect()
        XCTAssertNil(store.value?.deviceId)
        XCTAssertEqual(store.value?.server, "https://new.example.com")
    }
    func testPreferencesPersistNoCredentials() throws {
        let suite = "SyncBoxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesConnectionStore(defaults: defaults)
        try store.save(.init(server: "https://sync.example.com", allowHTTP: false, deviceId: "device-1", deviceName: "Mac"))
        let data = try XCTUnwrap(defaults.data(forKey: "syncbox.connection.preferences"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["server", "allowHTTP", "deviceId", "deviceName"]))
        XCTAssertEqual(try store.read()?.deviceId, "device-1")
    }
    func testLocalStoreRestoresTokenSeparatelyAndRemovesItOnLogout() throws {
        let suite = "SyncBoxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LocalSessionStore(defaults: defaults, directory: directory)
        var saved = SavedConnection(server: "https://sync.example.com", allowHTTP: false, deviceId: "device", deviceName: "Mac", token: "secret")
        try store.save(saved)
        XCTAssertEqual(try store.read()?.token, "secret")
        let prefs = try XCTUnwrap(defaults.data(forKey: "syncbox.connection.preferences"))
        XCTAssertFalse(String(decoding: prefs, as: UTF8.self).contains("secret"))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        saved.token = nil
        try store.save(saved)
        XCTAssertNil(try store.read()?.token)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path))
    }
    func testExpiredSessionClearsPersistedToken() async {
        let store = MemoryStore()
        store.value = .init(server: "https://sync.example.com", allowHTTP: false, deviceId: "device", deviceName: "Mac", token: "expired")
        StubURLProtocol.handler = { request in
            request.url!.path.hasSuffix("me") ? (401, "{\"message\":\"expired\"}") : (200, "{\"initialized\":true}")
        }
        let model = connection(store)
        await model.restore()
        XCTAssertEqual(model.stage, .credentials)
        XCTAssertNil(store.value?.token)
    }
    func testNetworkFailurePreservesSessionAndRetryResumes() async {
        let store = MemoryStore()
        store.value = .init(server: "https://sync.example.com", allowHTTP: false, deviceId: "device", deviceName: "Mac", token: "retained")
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let model = connection(store)
        await model.restore()
        XCTAssertEqual(store.value?.token, "retained")
        XCTAssertNotNil(model.error)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer retained")
            if request.url!.path.hasSuffix("/devices") {
                return (201, "{\"id\":\"device\",\"name\":\"Mac\",\"platform\":\"macos\",\"lastSeenAt\":\"now\"}")
            }
            return (200, "{\"username\":\"theo\",\"deviceId\":\"device\"}")
        }
        await model.connect()
        XCTAssertEqual(model.stage, .workspace)
        model.editServer()
        model.serverText = "https://different.example.com"
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, "{\"initialized\":true}")
        }
        await model.connect()
        XCTAssertNil(store.value?.token)
        XCTAssertNil(store.value?.deviceId)
    }
    func testInstallationIdentityPersistsIndependentlyOfSessionAndServer() throws {
        let suite = "SyncBoxIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LocalSessionStore(defaults: defaults, directory: directory)
        let id = try store.installationId()
        XCTAssertNotNil(UUID(uuidString: id))
        try store.save(.init(server: "https://first.example", allowHTTP: false, deviceId: nil, deviceName: "Mac", token: "secret"))
        try store.save(.init(server: "https://second.example", allowHTTP: false, deviceId: nil, deviceName: "Renamed"))
        XCTAssertEqual(try LocalSessionStore(defaults: defaults, directory: directory).installationId(), id)
        XCTAssertNotEqual(MemoryStore().identity, id)
    }

    func testResumeUpgradesDeviceAndRetriesStaleIDWithSameInstallation() async {
        for status in [404, 409] {
            let store = MemoryStore()
            store.value = .init(server: "https://sync.example.com", allowHTTP: false, deviceId: "old-id", deviceName: "Old name", token: "secret")
            var attempts: [[String: String]] = []
            StubURLProtocol.handler = { request in
                if request.url!.path.hasSuffix("/me") {
                    return (200, "{\"username\":\"owner\",\"deviceId\":\"old-id\"}")
                }
                XCTAssertTrue(request.url!.path.hasSuffix("/devices"))
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        data.append(contentsOf: buffer.prefix(count))
                    }
                }
                let body = try JSONDecoder().decode([String: String].self, from: data)
                attempts.append(body)
                if attempts.count == 1 { return (status, "{\"message\":\"stale device\"}") }
                return (201, "{\"id\":\"canonical-id\",\"name\":\"Saved name\",\"platform\":\"macos\",\"lastSeenAt\":\"now\"}")
            }
            let model = connection(store)
            await model.restore()
            XCTAssertNil(model.error)
            XCTAssertEqual(model.stage, .workspace)
            XCTAssertEqual(attempts.count, 2)
            XCTAssertEqual(attempts.first?["id"], "old-id")
            XCTAssertNil(attempts.last?["id"])
            XCTAssertTrue(attempts.allSatisfy { $0["installationId"] == store.identity })
            XCTAssertEqual(model.deviceId, "canonical-id")
            XCTAssertEqual(store.value?.deviceName, "Saved name")
        }
    }

    func testFailedSendPreservesDraftAndUnauthorizedExpiresSession() async {
        var expired = false
        let api = MockAPI { _, _, _, _ in throw APIError(message: "offline") }
        let model = WorkspaceModel(api: api, onUnauthorized: { expired = true })
        model.selected = conversation("one")
        model.draft = "不要丢失"
        await model.send()
        XCTAssertEqual(model.draft, "不要丢失")
        XCTAssertFalse(model.sending)
        api.handler = { _, _, _, _ in throw APIError(message: "expired", status: 401) }
        await model.loadConversations()
        XCTAssertTrue(expired)
    }
    func testSlowPreviousConversationCannotReplaceCurrentHistory() async {
        var continuation: CheckedContinuation<Data, Error>?
        let api = MockAPI { path, _, _, _ in
            if path.contains("/one/") { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return self.messagePage("two-message")
        }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        model.selected = conversation("one")
        let first = Task { await model.loadMessages() }
        while continuation == nil { await Task.yield() }
        model.selected = conversation("two")
        await model.loadMessages()
        continuation?.resume(returning: messagePage("one-message"))
        await first.value
        XCTAssertEqual(model.messages.items.first?.id, "two-message")
    }
    func testSuccessfulSendKeepsNewlyEditedDraft() async {
        var continuation: CheckedContinuation<Data, Error>?
        let api = MockAPI { _, method, _, _ in
            if method == "POST" { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return Data("{\"items\":[],\"page\":1,\"totalPages\":0,\"total\":0}".utf8)
        }
        let model = WorkspaceModel(api: api, onUnauthorized: {})
        model.selected = conversation("one")
        model.draft = "first"
        let task = Task { await model.send() }
        while continuation == nil { await Task.yield() }
        model.draft = "second"
        continuation?.resume(returning: Data("{\"id\":\"m\",\"content\":\"first\",\"createdAt\":\"now\",\"isStarred\":false}".utf8))
        await task.value
        XCTAssertEqual(model.draft, "second")
    }
}
