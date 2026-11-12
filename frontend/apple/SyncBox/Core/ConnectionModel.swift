import Foundation
import Observation

@MainActor @Observable
final class ConnectionModel {
    enum Stage { case server, credentials, workspace }
    var stage = Stage.server
    var serverText = ""
    var allowHTTP = false
    var deviceName: String
    var username = ""
    var initialized = true
    var requiresTwoFactor = false
    var busy = false
    var error: String?
    var workspace: WorkspaceModel?
    private(set) var api: APIClient?
    private(set) var deviceId: String?
    private var restored = false
    private let platform: String
    private let store: SessionStore
    private let factory: (URL) -> APIClient

    init(platform: String, deviceName: String, store: SessionStore = LocalSessionStore(), factory: @escaping (URL) -> APIClient = { APIClient(server: $0) }) {
        self.platform = platform
        self.deviceName = deviceName
        self.store = store
        self.factory = factory
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        await run {
            guard let saved = try self.store.read() else { return }
            self.serverText = saved.server
            self.allowHTTP = saved.allowHTTP
            self.deviceId = saved.deviceId
            self.deviceName = saved.deviceName
            let api = self.factory(try APIClient.normalizeServer(saved.server, allowHTTP: saved.allowHTTP))
            self.api = api
            api.token = saved.token
            try await self.resumeOrLoadStatus()
        }
    }

    func connect() async {
        await run {
            let url = try APIClient.normalizeServer(self.serverText, allowHTTP: self.allowHTTP)
            let saved = try self.store.read()
            if saved?.server != url.absoluteString { self.deviceId = nil; self.username = "" }
            self.serverText = url.absoluteString
            self.api = self.factory(url)
            if saved?.server == url.absoluteString { self.api?.token = saved?.token }
            try self.persist()
            try await self.resumeOrLoadStatus()
        }
    }

    func authenticate(password: String, code: String = "") async {
        await run {
            guard let api = self.api else { return }
            guard (6...128).contains(password.count) else { throw APIError(message: "密码长度需要为 6–128 位") }
            let name = self.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...80).contains(name.count) else { throw APIError(message: "设备名称需要为 1–80 个字符") }
            self.deviceName = name
            do {
                var body = ["username": self.username.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
                if self.initialized && !code.isEmpty { body["code"] = code.trimmingCharacters(in: .whitespacesAndNewlines) }
                let session: AuthSession = try await api.send(self.initialized ? "/auth/login" : "/auth/setup", body: body)
                self.initialized = true
                self.requiresTwoFactor = false
                self.username = session.user.username
                api.token = session.accessToken
                do {
                    try await self.registerDevice()
                    try self.persist()
                    self.enterWorkspace()
                } catch {
                    try? await api.remove("/auth/logout", method: "POST")
                    api.token = nil
                    throw error
                }
            } catch let error as APIError where error.code == "TWO_FACTOR_REQUIRED" {
                self.requiresTwoFactor = true
                throw APIError(message: "密码已验证，请输入验证器动态码或恢复码", status: error.status, code: error.code)
            } catch let error as APIError where error.status == 409 {
                self.initialized = true
                throw APIError(message: "服务已完成首次设置，请使用已有账号登录")
            }
        }
    }

    func renameDevice(_ name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let deviceId, (1...80).contains(name.count) else { throw APIError(message: "设备名称需要为 1–80 个字符") }
        let device: Device = try await api.send("/devices/\(deviceId)", method: "PATCH", body: ["name": name])
        deviceName = device.name
        try persist()
        await workspace?.loadDevices()
    }
    func logout() async {
        await run {
            do { try await self.api?.remove("/auth/logout", method: "POST") }
            catch let error as APIError where error.status == 401 { /* Already revoked. */ }
            self.workspace?.stopEvents()
            self.api?.token = nil
            self.workspace = nil
            self.username = ""
            self.stage = .credentials
            try self.persist()
        }
    }

    func resetLocalSession() {
        workspace?.stopEvents()
        api?.token = nil; workspace = nil; deviceId = nil; username = ""; initialized = false; requiresTwoFactor = false; error = nil; stage = .credentials
        do { try persist() } catch { self.error = userFacingError(error, fallback: "无法保存登录状态，请重试") }
    }
    func expire() {
        workspace?.stopEvents()
        api?.token = nil
        workspace = nil
        username = ""
        stage = .credentials
        initialized = true
        do { try persist(); error = "登录已失效，请重新登录" }
        catch { self.error = userFacingError(error) }
    }

    func editServer() {
        guard !busy else { return }
        workspace?.stopEvents()
        api = nil
        workspace = nil
        stage = .server
        error = nil
    }

    private func registerDevice() async throws {
        guard let api else { return }
        // Persist the installation marker before registering, so retries reuse it.
        var body = ["name": deviceName, "platform": platform, "installationId": try store.installationId()]
        if let deviceId { body["id"] = deviceId }
        let device: Device
        do { device = try await api.send("/devices", body: body) }
        catch let error as APIError where error.status == 404 || error.status == 409 {
            body.removeValue(forKey: "id")
            device = try await api.send("/devices", body: body)
        }
        deviceId = device.id
        deviceName = device.name
    }
    private func resumeOrLoadStatus() async throws {
        guard let api else { return }
        if api.token != nil {
            do {
                let account: Account = try await api.get("/auth/me")
                username = account.username
                deviceId = account.deviceId ?? deviceId
                // Also upgrade sessions created before installation IDs were introduced.
                try await registerDevice()
                try persist()
                enterWorkspace()
                return
            } catch let error as APIError where error.status == 401 {
                api.token = nil
                try persist()
            }
            // Network failures propagate without deleting the saved session.
        }
        try await loadStatus()
    }

    private func loadStatus() async throws {
        guard let api else { return }
        let status: ServerStatus = try await api.get("/auth/status")
        initialized = status.initialized
        stage = .credentials
    }
    private func enterWorkspace() {
        guard let api else { return }
        workspace = WorkspaceModel(api: api, onUnauthorized: { [weak self] in self?.expire() })
        workspace?.currentDeviceId = deviceId
        stage = .workspace
    }
    private func persist() throws {
        try store.save(.init(server: serverText, allowHTTP: allowHTTP, deviceId: deviceId, deviceName: deviceName, token: api?.token))
    }
    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() }
        catch { self.error = userFacingError(error) }
    }
}
