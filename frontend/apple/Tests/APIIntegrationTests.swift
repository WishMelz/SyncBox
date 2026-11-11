import XCTest
@testable import SyncBoxCore

final class APIIntegrationTests: XCTestCase {
    func testTwoDevicesShareConversationAndMessageLifecycle() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["SYNCBOX_TEST_SERVER"],
              let username = environment["SYNCBOX_TEST_USERNAME"],
              let password = environment["SYNCBOX_TEST_PASSWORD"] else {
            throw XCTSkip("设置 SYNCBOX_TEST_SERVER / USERNAME / PASSWORD 后运行独立测试后端联调")
        }
        let url = try APIClient.normalizeServer(address, allowHTTP: true)
        guard ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""), let port = url.port, port != 3000 else {
            throw APIError(message: "集成测试只允许独立端口上的本地测试服务，禁止使用默认 3000 端口")
        }
        let mac = APIClient(server: url), phone = APIClient(server: url)
        var conversationID: String?
        var deviceIDs: [String] = []
        func cleanup() async {
            if let conversationID { try? await mac.remove("/conversations/\(conversationID)") }
            for id in deviceIDs.reversed() { try? await mac.remove("/devices/\(id)") }
            try? await mac.remove("/auth/logout", method: "POST")
            try? await phone.remove("/auth/logout", method: "POST")
        }
        do {
            let status: ServerStatus = try await mac.get("/auth/status")
            XCTAssertTrue(status.initialized)
            for api in [mac, phone] {
                let login: AuthSession = try await api.send("/auth/login", body: ["username": username, "password": password])
                api.token = login.accessToken
                let device: Device = try await api.send("/devices", body: ["name": api === mac ? "Integration Mac" : "Integration iPhone", "platform": api === mac ? "macos" : "ios"])
                deviceIDs.append(device.id)
            }
            let conversation: Conversation = try await mac.send("/conversations", body: ["title": "Swift integration \(UUID().uuidString.prefix(8))"])
            conversationID = conversation.id
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAMElEQVRIiWMoT71BU8QwakHqaBDdGE1F5aMZ7cZoUVE+WpqmjlY45aNVZurgblUAAJKNHExSID/MAAAAAElFTkSuQmCC")!
            let picture = try await phone.sendImage(conversation.id, data: png, content: "Swift 图片联调")
            XCTAssertEqual(picture.image?.mimeType, "image/webp")
            XCTAssertEqual(picture.image?.width, 32)
            let bytes = try await mac.request("/messages/\(picture.id)/image")
            XCTAssertFalse(bytes.isEmpty)
            try await mac.remove("/messages/\(picture.id)")
            let sent: Message = try await phone.send("/conversations/\(conversation.id)/messages", body: ["content": "跨设备 中文 & %_? 内容"])
            let history: Page<Message> = try await mac.get("/conversations/\(conversation.id)/messages", query: ["q": "中文 & %_?"])
            XCTAssertEqual(history.items.first?.id, sent.id)
            XCTAssertEqual(history.items.first?.senderDevice?.platform, "ios")
            let annotated: Message = try await mac.send("/messages/\(sent.id)", method: "PATCH", body: ["annotation": "批注跨端检索关键词"])
            XCTAssertEqual(annotated.annotation, "批注跨端检索关键词")
            let notes: Page<Message> = try await phone.get("/conversations/\(conversation.id)/messages", query: ["q": "批注跨端检索关键词"])
            XCTAssertEqual(notes.items.first?.id, sent.id)
            XCTAssertEqual(notes.items.first?.annotation, annotated.annotation)
            let cleared: Message = try await phone.send("/messages/\(sent.id)", method: "PATCH", body: ["annotation": ""])
            XCTAssertEqual(cleared.annotation, "")
            let starred: Message = try await mac.send("/messages/\(sent.id)", method: "PATCH", body: ["isStarred": true])
            XCTAssertTrue(starred.isStarred)
            let detail: Message = try await phone.get("/messages/\(sent.id)")
            XCTAssertTrue(detail.isStarred)
            let renamed: Conversation = try await phone.send("/conversations/\(conversation.id)", method: "PATCH", body: ["title": "联调已重命名"])
            XCTAssertEqual(renamed.title, "联调已重命名")
            try await mac.remove("/messages/\(sent.id)")
            let empty: Page<Message> = try await phone.get("/conversations/\(conversation.id)/messages")
            XCTAssertEqual(empty.total, 0)
            await cleanup()
        } catch {
            await cleanup()
            throw error
        }
    }
}
