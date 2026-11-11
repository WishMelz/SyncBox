import Foundation

struct ServerStatus: Decodable { let initialized: Bool }
struct Account: Decodable { let username: String; let deviceId: String? }
struct AuthSession: Decodable { let accessToken: String; let user: Account }
struct Device: Decodable, Identifiable {
    let id: String
    let name: String
    let platform: String
    let lastSeenAt: String
    let online: Bool?
}
struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let preview: String?
    let messageCount: Int?
    var isPinned: Bool? = nil
    var unreadCount: Int? = nil
}
struct SenderDevice: Decodable { let name: String; let platform: String; var id: String? = nil }
struct Attachment: Decodable, Identifiable {
    let id: String; let name: String; let size: Int
    let mimeType: String
    var hasPreview: Bool? = nil
    var deletedAt: Double? = nil
}
struct PendingFile: Identifiable, Equatable {
    let id = UUID(); let name: String; let data: Data
}
struct MessageImageInfo: Decodable { let mimeType: String; let width: Int; let height: Int; let size: Int }
struct Message: Decodable, Identifiable {
    var isRead: Bool? = nil
    var conversationId: String? = nil
    var conversationTitle: String? = nil
    var attachments: [Attachment]? = nil
    var filesExpired: Bool? = nil
    var annotation: String? = nil
    var image: MessageImageInfo? = nil
    let id: String
    let content: String
    let createdAt: String
    let isStarred: Bool
    let senderDevice: SenderDevice?
    var displayDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) else { return createdAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let page: Int
    let totalPages: Int
    let total: Int
    var hasMore: Bool? = nil
    var nextCursor: String? = nil
    static var empty: Self { .init(items: [], page: 1, totalPages: 0, total: 0) }
}
struct APIError: LocalizedError {
    let message: String
    var status: Int? = nil
    var code: String? = nil
    var errorDescription: String? { message }
}

struct SyncEvent: Decodable {
    let type: String
    let scope: String
    let conversationId: String?
    let messageId: String?
    let at: Double?
}
