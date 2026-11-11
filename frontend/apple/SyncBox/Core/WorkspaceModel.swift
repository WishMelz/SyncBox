import Foundation
import Observation

@MainActor @Observable
final class WorkspaceModel {
    var conversations: Page<Conversation> = .empty
    var messages: Page<Message> = .empty
    var selected: Conversation? {
        didSet {
            if selected?.id != oldValue?.id {
                messageQuery = ""
                messagePage = 1
                messageRevision += 1
                messages = messageHistory.page
            }
        }
    }
    var conversationQuery = ""
    var messageQuery = "" {
        didSet {
            if oldValue != messageQuery {
                messageRevision += 1
                messages = messageHistory.page
            }
        }
    }
    var conversationPage = 1
    var messagePage = 1
    var devices: [Device] = []
    var currentDeviceId: String?
    var favorites: Page<Message> = .empty
    var favoriteQuery = ""
    var favoritePage = 1
    var lastSynced: Date?
    var fileDrafts: [String: [PendingFile]] = [:]
    private var favoriteRevision = 0
    var error: String?
    var loading = false
    var sending = false
    var scrollToLatest = 0
    var mutating = false
    var drafts: [String: String] = [:]
    var imageDrafts: [String: Data] = [:]
    private var listRevision = 0
    private var messageRevision = 0
    private var markingRead = Set<String>()
    private var historyCache: [String: MessageHistory] = [:]
    private var historyOrder: [String] = []
    var historyKey: String { (selected?.id ?? "") + ":" + messageQuery }
    var messageHistory: MessageHistory {
        if let cached = historyCache[historyKey] { return cached }
        let id = selected?.id ?? "", query = messageQuery, api = api
        let history = MessageHistory { cursors in
            var params = ["q": String(query.prefix(200)), "page": "1", "pageSize": "30"]
            params.merge(cursors) { _, new in new }
            return try await api.get("/conversations/\(id)/messages", query: params)
        }
        historyCache[historyKey] = history
        historyOrder.append(historyKey)
        if historyOrder.count > 20 { historyCache.removeValue(forKey: historyOrder.removeFirst()) }
        return history
    }
    private struct SendAttempt {
        let clientId = UUID().uuidString
        let content: String
        let image: Data?
        let files: [PendingFile]
    }
    private var sendAttempts: [String: SendAttempt] = [:]
    private var eventsTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var eventsGeneration = 0
    private var pendingEventScopes = Set<String>()
    private(set) var realtimeConnected = false
    private let api: APITransport
    private let onUnauthorized: () -> Void

    init(api: APITransport, onUnauthorized: @escaping () -> Void) {
        self.api = api
        self.onUnauthorized = onUnauthorized
    }
    func startEvents() {
        guard eventsTask == nil else { return }
        eventsGeneration += 1
        let api = self.api
        eventsTask = Task { [weak self] in
            var delay = 3
            while !Task.isCancelled {
                do {
                    for try await event in api.events() {
                        if Task.isCancelled { return }
                        if event.type == "connected" {
                            delay = 3
                            self?.realtimeConnected = true
                            self?.queueEventRefresh("all")
                        } else if event.type == "invalidate" {
                            self?.queueEventRefresh(event.scope)
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    if (error as? APIError)?.status == 401 {
                        self?.handle(error)
                        self?.stopEvents()
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                self?.realtimeConnected = false
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 30)
            }
        }
    }
    private func queueEventRefresh(_ scope: String) {
        pendingEventScopes.insert(scope)
        guard eventRefreshTask == nil else { return }
        let generation = eventsGeneration
        eventRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            defer { if self.eventsGeneration == generation { self.eventRefreshTask = nil } }
            while !Task.isCancelled && !self.pendingEventScopes.isEmpty {
                let scopes = self.pendingEventScopes
                self.pendingEventScopes.removeAll()
                if !scopes.isDisjoint(with: ["all", "conversations", "messages", "favorites", "settings"]) {
                    await self.refresh()
                }
                guard !Task.isCancelled else { return }
                if !scopes.isDisjoint(with: ["all", "messages", "favorites", "settings"]) { await self.loadFavorites() }
                guard !Task.isCancelled else { return }
                if scopes.contains("all") || scopes.contains("devices") { await self.loadDevices() }
            }
        }
    }
    func stopEvents() {
        eventsGeneration += 1
        eventsTask?.cancel()
        eventsTask = nil
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
        pendingEventScopes.removeAll()
        realtimeConnected = false
    }
    var draft: String {
        get { selected.flatMap { drafts[$0.id] } ?? "" }
        set { if let id = selected?.id { drafts[id] = newValue } }
    }
    var canSend: Bool {
        !sending && selected != nil && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.flatMap { imageDrafts[$0.id] } != nil || !(selected.flatMap { fileDrafts[$0.id] } ?? []).isEmpty) && draft.count <= 50_000
    }
    func refresh() async {
        await loadConversations()
        guard !Task.isCancelled else { return }
        await loadMessages()
        if error == nil { lastSynced = Date() }
    }
    func loadConversations(failureMessage: String? = nil) async {
        listRevision += 1
        let revision = listRevision, query = conversationQuery, page = conversationPage
        loading = true
        defer { if revision == listRevision { loading = false } }
        do {
            let result: Page<Conversation> = try await api.get("/conversations", query: parameters(query, page))
            guard revision == listRevision, query == conversationQuery, page == conversationPage, !Task.isCancelled else { return }
            conversations = result
            error = nil
            if page > max(1, result.totalPages) { conversationPage = max(1, result.totalPages); await loadConversations(failureMessage: failureMessage) }
            if let updated = result.items.first(where: { $0.id == selected?.id }) { selected = updated }
        } catch { if revision == listRevision { handle(error, message: failureMessage) } }
    }
    func loadMessages(failureMessage: String? = nil) async {
        guard let id = selected?.id else { return }
        messageRevision += 1
        let revision = messageRevision, query = messageQuery, history = messageHistory
        do {
            try await history.refresh()
            guard revision == messageRevision, selected?.id == id, query == messageQuery, !Task.isCancelled else { return }
            messages = history.page
            if query.isEmpty && ((selected?.unreadCount ?? 0) > 0 || messages.items.contains(where: { $0.isRead == false })) {
                await markRead(id, failureMessage: failureMessage)
            }
            guard revision == messageRevision, selected?.id == id, !Task.isCancelled else { return }
        } catch {
            guard revision == messageRevision, selected?.id == id else { return }
            if (error as? APIError)?.status == 404 { selected = nil }
            handle(error, message: failureMessage)
        }
    }
    func loadOlderMessages() async {
        guard selected != nil else { return }
        let key = historyKey, history = messageHistory
        do {
            try await history.loadOlder()
            if key == historyKey { messages = history.page }
        } catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
        }
    }
    /// Mark the active conversation as read on the server. The list is refreshed so
    /// unread badges stay in sync on every device.
    func markRead(_ conversationID: String, failureMessage: String? = nil) async {
        guard markingRead.insert(conversationID).inserted else { return }
        defer { markingRead.remove(conversationID) }
        do {
            try await api.remove("/conversations/\(conversationID)/read", method: "PATCH")
            await loadConversations(failureMessage: failureMessage)
        } catch { handle(error, message: failureMessage) }
    }
    @discardableResult func saveConversation(title: String, editing: Conversation?) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(title.count), !mutating else { return false }
        mutating = true
        defer { mutating = false }
        do {
            let conversation: Conversation = try await api.send(editing.map { "/conversations/\($0.id)" } ?? "/conversations", method: editing == nil ? "POST" : "PATCH", body: ["title": title])
            selected = conversation
            conversationQuery = ""
            conversationPage = 1
            await refresh()
            return true
        } catch { handle(error); return false }
    }
    func deleteConversation(_ conversation: Conversation) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do {
            try await api.remove("/conversations/\(conversation.id)")
            drafts.removeValue(forKey: conversation.id)
            imageDrafts.removeValue(forKey: conversation.id)
            fileDrafts.removeValue(forKey: conversation.id)
            sendAttempts.removeValue(forKey: conversation.id)
            historyCache = historyCache.filter { !$0.key.hasPrefix(conversation.id + ":") }
            historyOrder.removeAll { $0.hasPrefix(conversation.id + ":") }
            if selected?.id == conversation.id { selected = nil }
            await loadConversations()
        } catch { handle(error) }
    }
    func send() async {
        guard canSend, let id = selected?.id else { return }
        let content = draft
        let files = fileDrafts[id] ?? []
        let image = files.isEmpty ? imageDrafts[id] : nil
        let previous = sendAttempts[id]
        let attempt = previous?.content == content && previous?.image == image && previous?.files == files
            ? previous! : SendAttempt(content: content, image: image, files: files)
        sendAttempts[id] = attempt
        let clientId = attempt.clientId
        sending = true
        error = nil
        defer { sending = false }
        do {
            if !files.isEmpty { let _ = try await api.sendFiles(id, files: files, content: content, clientId: clientId) }
            else if let image { let _ = try await api.sendImage(id, data: image, content: content, clientId: clientId) }
            else { let _: Message = try await api.send("/conversations/\(id)/messages", body: ["content": content, "clientId": clientId]) }
            sendAttempts.removeValue(forKey: id)
            if fileDrafts[id] == files { fileDrafts.removeValue(forKey: id) }
            if imageDrafts[id] == image { imageDrafts.removeValue(forKey: id) }
            if drafts[id] == content { drafts[id] = "" }
            // Delivery has already succeeded. A subsequent read failure must
            // not be presented as a failed send or restore the submitted draft.
            let refreshFailure = "消息已发送，列表刷新失败，请刷新查看。"
            await loadConversations(failureMessage: refreshFailure)
            if selected?.id == id {
                messageQuery = ""
                messagePage = 1
                await loadMessages(failureMessage: refreshFailure)
                scrollToLatest += 1
            }
        } catch { handle(error) }
    }
    func imageData(_ id: String) async -> Data? {
        do { return try await api.request("/messages/\(id)/image", method: "GET", query: [:], body: nil) }
        catch { handle(error); return nil }
    }

    func saveAnnotation(_ message: Message, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.count <= 2000 else { throw APIError(message: "批注最多 2000 字") }
        guard !mutating else { throw APIError(message: "请等待当前操作完成") }
        mutating = true
        do {
            let _: Message = try await api.send("/messages/\(message.id)", method: "PATCH", body: ["annotation": text])
            mutating = false
            await refresh()
            await loadFavorites()
        } catch {
            mutating = false
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func toggleStar(_ message: Message) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do {
            let _: Message = try await api.send("/messages/\(message.id)", method: "PATCH", body: ["isStarred": !message.isStarred])
            await loadMessages()
            await loadFavorites()
        } catch { handle(error) }
    }
    func deleteMessage(_ message: Message) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do { try await api.remove("/messages/\(message.id)"); await refresh(); await loadFavorites() }
        catch { handle(error) }
    }
    func togglePin(_ conversation: Conversation) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do {
            let _: Conversation = try await api.send("/conversations/\(conversation.id)", method: "PATCH", body: ["pinned": !(conversation.isPinned ?? false)])
            await loadConversations()
        } catch { handle(error) }
    }
    func loadFavorites() async {
        favoriteRevision += 1
        let revision = favoriteRevision, query = favoriteQuery, page = favoritePage
        do {
            let result: Page<Message> = try await api.get("/messages/starred", query: parameters(query, page))
            guard revision == favoriteRevision, query == favoriteQuery, page == favoritePage, !Task.isCancelled else { return }
            favorites = result
            if page > max(1, result.totalPages) { favoritePage = max(1, result.totalPages); await loadFavorites() }
        } catch { if revision == favoriteRevision { handle(error) } }
    }
    func openConversation(_ message: Message) async -> Bool {
        guard let id = message.conversationId else { return false }
        do {
            let conversation: Conversation = try await api.get("/conversations/\(id)")
            selected = conversation
            await loadMessages()
            return true
        } catch { handle(error); return false }
    }
    func attachmentData(_ message: Message, file: Attachment, preview: Bool = false) async throws -> Data {
        do { return try await api.request("/messages/\(message.id)/attachments/\(file.id)" + (preview ? "/preview" : ""), method: "GET", query: [:], body: nil) }
        catch { handle(error); throw error }
    }
    func loadDevices() async {
        do { devices = try await api.get("/devices") }
        catch { handle(error) }
    }
    private func parameters(_ query: String, _ page: Int) -> [String: String] {
        ["q": String(query.prefix(200)), "page": String(page), "pageSize": "30"]
    }
    private func handle(_ error: Error, message: String? = nil) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if (error as? APIError)?.status == 401 { onUnauthorized() }
        else { self.error = message ?? error.localizedDescription }
    }
}
