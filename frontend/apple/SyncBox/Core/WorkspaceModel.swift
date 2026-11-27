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
    var files: Page<FileItem> = .empty
    var fileQuery = ""
    var fileCategory = "all"
    var fileSort = "newest"
    var filePage = 1
    var filesLoading = false
    var favoritesOpen = false
    var filesOpen = false
    var devicesOpen = false
    var settingsOpen = false
    private(set) var settingsRevision = 0
    var lastSynced: Date?
    var fileDrafts: [String: [PendingFile]] = [:]
    private var favoriteRevision = 0
    private var fileRevision = 0
    var error: String?
    var loading = false
    var sending = false
    var uploadProgress: UploadProgress?
    private var uploadCancelled = false
    var scrollToLatest = 0
    var mutatingConversation = false
    var mutatingMessageIDs: Set<String> = []
    var mutating: Bool { mutatingConversation || !mutatingMessageIDs.isEmpty }
    func isMutatingMessage(_ id: String) -> Bool {
        mutatingConversation || mutatingMessageIDs.contains(id)
    }

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

    private struct SyncBatch {
        var fullReconcile = false
        var scopes = Set<String>()
        var conversationIds = Set<String>()
        var messageIdsByConversation: [String: Set<String>] = [:]
        var wildcardMessageConversations = Set<String>()
        var hasGlobalWildcardMessage = false

        var isEmpty: Bool {
            !fullReconcile && scopes.isEmpty
        }

        mutating func add(_ event: SyncEvent) {
            if event.type == "connected" || event.scope == "all" {
                fullReconcile = true
                return
            }
            guard !event.scope.isEmpty else { return }
            scopes.insert(event.scope)
            if let conversationId = event.conversationId, !conversationId.isEmpty {
                conversationIds.insert(conversationId)
            }
            if event.scope == "messages" {
                if let conversationId = event.conversationId, !conversationId.isEmpty {
                    if let messageId = event.messageId, !messageId.isEmpty {
                        var set = messageIdsByConversation[conversationId] ?? []
                        set.insert(messageId)
                        messageIdsByConversation[conversationId] = set
                    } else {
                        wildcardMessageConversations.insert(conversationId)
                    }
                } else {
                    hasGlobalWildcardMessage = true
                }
            }
        }
    }

    private var sendAttempts: [String: SendAttempt] = [:]
    private var eventsTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var eventsGeneration = 0
    private var pendingBatch = SyncBatch()
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
        reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh(reconcile: true)
            }
        }
        eventsTask = Task { [weak self] in
            var delay = 3
            while !Task.isCancelled {
                do {
                    for try await event in api.events() {
                        if Task.isCancelled { return }
                        if event.type == "connected" {
                            delay = 3
                            self?.realtimeConnected = true
                            self?.queueEventRefresh(
                                .init(type: "connected", scope: "all", conversationId: nil, messageId: nil, at: nil)
                            )
                        } else if event.type == "invalidate" {
                            self?.queueEventRefresh(event)
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

    private func queueEventRefresh(_ event: SyncEvent) {
        pendingBatch.add(event)
        guard eventRefreshTask == nil else { return }
        let generation = eventsGeneration
        eventRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            defer { if self.eventsGeneration == generation { self.eventRefreshTask = nil } }
            while !Task.isCancelled && !self.pendingBatch.isEmpty {
                let batch = self.pendingBatch
                self.pendingBatch = SyncBatch()
                await self.applyEventBatch(batch)
            }
        }
    }

    private func applyEventBatch(_ batch: SyncBatch) async {
        if batch.fullReconcile {
            await refresh(reconcile: true)
            guard !Task.isCancelled else { return }
            if favoritesOpen { await loadFavorites() }
            guard !Task.isCancelled else { return }
            if filesOpen { await loadFiles() }
            guard !Task.isCancelled else { return }
            if devicesOpen { await loadDevices() }
            if settingsOpen { settingsRevision += 1 }
            return
        }

        let scopes = batch.scopes
        var syncedNetwork = false

        if scopes.contains("conversations") {
            await loadConversations()
            syncedNetwork = true
        }
        guard !Task.isCancelled else { return }

        if let selectedId = selected?.id {
            let selectedConvInvalidated =
                scopes.contains("conversations") && batch.conversationIds.contains(selectedId)
            let hasWildcard =
                batch.hasGlobalWildcardMessage || batch.wildcardMessageConversations.contains(selectedId)
            let ids = batch.messageIdsByConversation[selectedId]

            if hasWildcard || selectedConvInvalidated {
                await loadMessages(reconcile: false)
                syncedNetwork = true
            } else if let ids, !ids.isEmpty {
                let history = messageHistory
                if messageQuery.isEmpty && history.ready && ids.count <= 3 {
                    await patchSelectedMessages(conversationId: selectedId, messageIds: Array(ids), history: history)
                } else {
                    await loadMessages(reconcile: false)
                }
                syncedNetwork = true
            }
        }
        guard !Task.isCancelled else { return }

        if favoritesOpen && scopes.contains("favorites") {
            await loadFavorites()
            syncedNetwork = true
        }
        guard !Task.isCancelled else { return }

        if filesOpen && !scopes.isDisjoint(with: ["messages", "conversations", "settings"]) {
            await loadFiles()
            syncedNetwork = true
        }
        guard !Task.isCancelled else { return }

        if devicesOpen && scopes.contains("devices") {
            await loadDevices()
            syncedNetwork = true
        }
        if settingsOpen && scopes.contains("settings") {
            settingsRevision += 1
        }
        if syncedNetwork && error == nil {
            lastSynced = Date()
        }
    }

    private func patchSelectedMessages(
        conversationId: String,
        messageIds: [String],
        history: MessageHistory
    ) async {
        messageRevision += 1
        let revision = messageRevision
        let query = messageQuery
        do {
            for messageId in messageIds {
                guard revision == messageRevision, selected?.id == conversationId, query == messageQuery, !Task.isCancelled else {
                    return
                }
                do {
                    let detail = try await api.messageDetail(messageId)
                    guard revision == messageRevision, selected?.id == conversationId, query == messageQuery else { return }
                    if detail.conversationId == nil || detail.conversationId == conversationId {
                        history.upsertMessage(detail)
                    }
                } catch let err as APIError where err.status == 404 {
                    guard revision == messageRevision, selected?.id == conversationId else { return }
                    history.removeMessage(messageId)
                    api.invalidateMessageMediaCache(messageId)
                }
            }
            guard revision == messageRevision, selected?.id == conversationId, query == messageQuery, !Task.isCancelled else {
                return
            }
            messages = history.page
            if query.isEmpty && ((selected?.unreadCount ?? 0) > 0 || messages.items.contains(where: { $0.isRead == false })) {
                await markRead(conversationId)
            }
        } catch {
            if revision == messageRevision, selected?.id == conversationId {
                handle(error)
            }
        }
    }

    func stopEvents() {
        eventsGeneration += 1
        eventsTask?.cancel()
        eventsTask = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
        pendingBatch = SyncBatch()
        realtimeConnected = false
    }

    var draft: String {
        get { selected.flatMap { drafts[$0.id] } ?? "" }
        set { if let id = selected?.id { drafts[id] = newValue } }
    }
    var canSend: Bool {
        !sending && selected != nil && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.flatMap { imageDrafts[$0.id] } != nil || !(selected.flatMap { fileDrafts[$0.id] } ?? []).isEmpty) && draft.count <= 50_000
    }

    func refresh(reconcile: Bool = false) async {
        await loadConversations()
        guard !Task.isCancelled else { return }
        await loadMessages(reconcile: reconcile)
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

    func loadMessages(failureMessage: String? = nil, reconcile: Bool = false) async {
        guard let id = selected?.id else { return }
        messageRevision += 1
        let revision = messageRevision, query = messageQuery, history = messageHistory
        do {
            if reconcile {
                try await history.reconcile()
            } else {
                try await history.refreshLatest()
            }
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
        mutatingConversation = true
        defer { mutatingConversation = false }
        do {
            let conversation: Conversation = try await api.send(editing.map { "/conversations/\($0.id)" } ?? "/conversations", method: editing == nil ? "POST" : "PATCH", body: ["title": title])
            selected = conversation
            conversationQuery = ""
            conversationPage = 1
            await refresh(reconcile: false)
            return true
        } catch { handle(error); return false }
    }

    func deleteConversation(_ conversation: Conversation) async {
        guard !mutating else { return }
        mutatingConversation = true
        defer { mutatingConversation = false }
        do {
            try await api.remove("/conversations/\(conversation.id)")
            api.clearMediaCache()
            drafts.removeValue(forKey: conversation.id)
            imageDrafts.removeValue(forKey: conversation.id)
            if let existingFiles = fileDrafts.removeValue(forKey: conversation.id) {
                for file in existingFiles { file.cleanup() }
            }
            sendAttempts.removeValue(forKey: conversation.id)
            historyCache = historyCache.filter { !$0.key.hasPrefix(conversation.id + ":") }
            historyOrder.removeAll { $0.hasPrefix(conversation.id + ":") }
            if selected?.id == conversation.id { selected = nil }
            await loadConversations()
            if filesOpen { await loadFiles() }
        } catch { handle(error) }
    }

    func removeFileDraft(_ file: PendingFile, for conversationID: String) {
        guard var list = fileDrafts[conversationID] else { return }
        list.removeAll { $0.id == file.id }
        fileDrafts[conversationID] = list
        file.cleanup()
    }

    func clearFileDrafts(for conversationID: String) {
        if let existing = fileDrafts.removeValue(forKey: conversationID) {
            for file in existing { file.cleanup() }
        }
    }

    func cancelUpload() {
        uploadCancelled = true
        api.cancelCurrentUpload()
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
        uploadCancelled = false
        uploadProgress = nil
        error = nil
        defer {
            sending = false
            uploadProgress = nil
            uploadCancelled = false
        }
        do {
            if !files.isEmpty {
                let totalBytes = Int64(files.reduce(0, { $0 + $1.size }))
                uploadProgress = UploadProgress(loaded: 0, total: totalBytes)
                _ = try await api.sendFiles(id, files: files, content: content, clientId: clientId) { [weak self] progress in
                    self?.uploadProgress = progress
                }
            }
            else if let image { _ = try await api.sendImage(id, data: image, content: content, clientId: clientId) }
            else { let _: Message = try await api.send("/conversations/\(id)/messages", body: ["content": content, "clientId": clientId]) }
            sendAttempts.removeValue(forKey: id)
            if fileDrafts[id] == files {
                fileDrafts.removeValue(forKey: id)
                for file in files { file.cleanup() }
            }
            if imageDrafts[id] == image { imageDrafts.removeValue(forKey: id) }
            if drafts[id] == content { drafts[id] = "" }
            // Delivery has already succeeded. A subsequent read failure must
            // not be presented as a failed send or restore the submitted draft.
            let refreshFailure = "消息已发送，列表刷新失败，请刷新查看。"
            await loadConversations(failureMessage: refreshFailure)
            if selected?.id == id {
                messageQuery = ""
                messagePage = 1
                await loadMessages(failureMessage: refreshFailure, reconcile: false)
                scrollToLatest += 1
            }
            if filesOpen { await loadFiles() }
        } catch {
            if uploadCancelled { return }
            handle(error)
        }
    }

    func imageData(_ id: String) async -> Data? {
        do { return try await api.imageData(id) }
        catch { handle(error); return nil }
    }

    func editMessage(_ message: Message, content: String) async throws {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 50_000 else { throw APIError(message: "消息正文需为 1–50,000 个字符") }
        guard !isMutatingMessage(message.id) else { throw APIError(message: "请等待当前操作完成") }
        mutatingMessageIDs.insert(message.id)
        defer { mutatingMessageIDs.remove(message.id) }
        do {
            let _: Message = try await api.editMessage(message.id, content: value)
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
        } catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func deleteAttachment(_ message: Message, file: Attachment) async throws {
        guard !isMutatingMessage(message.id) else { throw APIError(message: "请等待当前操作完成") }
        mutatingMessageIDs.insert(message.id)
        defer { mutatingMessageIDs.remove(message.id) }
        do {
            try await api.removeAttachment(message.id, attachmentID: file.id)
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
            if filesOpen { await loadFiles() }
        } catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func deleteImage(_ message: Message) async throws {
        guard !isMutatingMessage(message.id) else { throw APIError(message: "请等待当前操作完成") }
        mutatingMessageIDs.insert(message.id)
        defer { mutatingMessageIDs.remove(message.id) }
        do {
            try await api.removeImage(message.id)
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
            if filesOpen { await loadFiles() }
        } catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func saveAnnotation(_ message: Message, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.count <= 2000 else { throw APIError(message: "批注最多 2000 字") }
        guard !isMutatingMessage(message.id) else { throw APIError(message: "请等待当前操作完成") }
        mutatingMessageIDs.insert(message.id)
        do {
            let _: Message = try await api.send("/messages/\(message.id)", method: "PATCH", body: ["annotation": text])
            mutatingMessageIDs.remove(message.id)
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
        } catch {
            mutatingMessageIDs.remove(message.id)
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func toggleStar(_ message: Message) async {
        guard !isMutatingMessage(message.id) else { return }
        mutatingMessageIDs.insert(message.id)
        defer { mutatingMessageIDs.remove(message.id) }
        do {
            let _: Message = try await api.send("/messages/\(message.id)", method: "PATCH", body: ["isStarred": !message.isStarred])
            await loadMessages(reconcile: false)
            if favoritesOpen { await loadFavorites() }
        } catch { handle(error) }
    }

    func deleteMessage(_ message: Message) async {
        guard !isMutatingMessage(message.id) else { return }
        mutatingMessageIDs.insert(message.id)
        defer { mutatingMessageIDs.remove(message.id) }
        do {
            try await api.remove("/messages/\(message.id)")
            api.invalidateMessageMediaCache(message.id)
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
            if filesOpen { await loadFiles() }
        } catch { handle(error) }
    }

    func togglePin(_ conversation: Conversation) async {
        guard !mutating else { return }
        mutatingConversation = true
        defer { mutatingConversation = false }
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

    func loadFiles() async {
        fileRevision += 1
        let revision = fileRevision, query = fileQuery, category = fileCategory, sort = fileSort, page = filePage
        filesLoading = true
        defer { if revision == fileRevision { filesLoading = false } }
        do {
            let result = try await api.files(query: query, category: category, sort: sort, page: page)
            guard revision == fileRevision, query == fileQuery, category == fileCategory, sort == fileSort, page == filePage, !Task.isCancelled else { return }
            files = result
            if page > max(1, result.totalPages) { filePage = max(1, result.totalPages); await loadFiles() }
        } catch { if revision == fileRevision { handle(error) } }
    }

    func deleteFile(_ file: FileItem) async throws {
        guard !isMutatingMessage(file.messageId) else { throw APIError(message: "请等待当前操作完成") }
        mutatingMessageIDs.insert(file.messageId)
        defer { mutatingMessageIDs.remove(file.messageId) }
        do {
            try await api.deleteFile(file)
            await loadFiles()
            await refresh(reconcile: false)
            if favoritesOpen { await loadFavorites() }
        } catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
    }

    func openConversation(_ message: Message) async -> Bool {
        guard let id = message.conversationId else { return false }
        do {
            let conversation: Conversation = try await api.get("/conversations/\(id)")
            selected = conversation
            await loadMessages(reconcile: false)
            return true
        } catch { handle(error); return false }
    }

    func attachmentData(_ message: Message, file: Attachment, preview: Bool = false) async throws -> Data {
        do { return try await api.attachmentData(message.id, attachmentID: file.id, preview: preview) }
        catch { handle(error); throw error }
    }

    func downloadBackup() async throws -> BackupPayload {
        do { return try await api.downloadBackup() }
        catch {
            if (error as? APIError)?.status == 401 { onUnauthorized() }
            throw error
        }
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
        else { self.error = message ?? userFacingError(error) }
    }
}
