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
    let id: UUID
    let name: String
    let size: Int
    let data: Data
    let fileURL: URL?
    let ownsFile: Bool

    init(name: String, data: Data) {
        self.id = UUID()
        self.name = name
        self.size = data.count
        self.data = data
        self.fileURL = nil
        self.ownsFile = false
    }

    init(name: String, size: Int, fileURL: URL, ownsFile: Bool = true) {
        self.id = UUID()
        self.name = name
        self.size = size
        self.data = Data()
        self.fileURL = fileURL
        self.ownsFile = ownsFile
    }

    func cleanup() {
        guard ownsFile, let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func == (lhs: PendingFile, rhs: PendingFile) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.size == rhs.size &&
        lhs.data == rhs.data &&
        lhs.fileURL == rhs.fileURL
    }
}

struct UploadProgress: Equatable, Sendable {
    let loaded: Int64
    let total: Int64

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(loaded) / Double(total), 0), 1)
    }

    var percent: Int {
        guard total > 0 else { return 100 }
        return min(max(Int((loaded * 100) / total), 0), 100)
    }
}

struct FileItem: Decodable, Identifiable, Equatable {
    let id: String
    let messageId: String
    let kind: String
    let category: String
    let name: String
    let mimeType: String
    let size: Int
    let hasPreview: Bool
    let width: Int?
    let height: Int?
    let conversationId: String
    let conversationTitle: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, messageId, kind, category, name, mimeType, size, hasPreview, width, height, conversationId, conversationTitle, createdAt
    }

    init(
        id: String,
        messageId: String,
        kind: String,
        category: String,
        name: String,
        mimeType: String,
        size: Int,
        hasPreview: Bool,
        width: Int? = nil,
        height: Int? = nil,
        conversationId: String,
        conversationTitle: String,
        createdAt: String
    ) {
        self.id = id
        self.messageId = messageId
        self.kind = kind
        self.category = category
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.hasPreview = hasPreview
        self.width = width
        self.height = height
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messageId = try container.decode(String.self, forKey: .messageId)
        let decodedKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "attachment"
        kind = decodedKind
        category = try container.decodeIfPresent(String.self, forKey: .category)
            ?? (decodedKind == "image" ? "image" : "file")
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "文件"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        hasPreview = try container.decodeIfPresent(Bool.self, forKey: .hasPreview) ?? false
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        conversationTitle = try container.decodeIfPresent(String.self, forKey: .conversationTitle) ?? ""
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    var asAttachment: Attachment {
        Attachment(id: id, name: name, size: size, mimeType: mimeType, hasPreview: hasPreview)
    }

    var asMessageShell: Message {
        Message(
            conversationId: conversationId,
            conversationTitle: conversationTitle,
            id: messageId,
            content: "",
            createdAt: createdAt,
            isStarred: false,
            senderDevice: nil
        )
    }
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
    var hasTotal: Bool = true

    init(
        items: [Item],
        page: Int,
        totalPages: Int,
        total: Int,
        hasMore: Bool? = nil,
        nextCursor: String? = nil,
        hasTotal: Bool = true
    ) {
        self.items = items
        self.page = page
        self.totalPages = totalPages
        self.total = total
        self.hasMore = hasMore
        self.nextCursor = nextCursor
        self.hasTotal = hasTotal
    }

    private enum CodingKeys: String, CodingKey {
        case items, page, totalPages, total, hasMore, nextCursor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Item].self, forKey: .items)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        hasTotal = container.contains(.total)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    static var empty: Self { .init(items: [], page: 1, totalPages: 0, total: 0) }
}
struct APIError: LocalizedError {
    let message: String
    var status: Int? = nil
    var code: String? = nil
    var errorDescription: String? { message }
}

func userFacingError(_ error: Error, fallback: String = "操作失败，请重试") -> String {
    if let apiError = error as? APIError { return apiError.message }
    if error is URLError { return "网络连接失败，请重试" }
    return fallback
}

struct SyncEvent: Decodable {
    let type: String
    let scope: String
    let conversationId: String?
    let messageId: String?
    let at: Double?
}
