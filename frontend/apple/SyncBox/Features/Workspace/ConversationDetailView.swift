import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ConversationDetailView: View {
    @Bindable var model: WorkspaceModel
    let conversation: Conversation
    let rename: () -> Void
    let delete: () -> Void
    var compact = false
    @State private var annotatingMessage: Message?
    @State private var deletingMessage: Message?
    @State private var copiedID: String?
    @State private var choosingImage = false
    @State private var choosingFiles = false
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool
    private var orderedMessages: [Message] { Array(model.messages.items.reversed()) }
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if searchOpen {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索消息、批注或文件名", text: $model.messageQuery).textFieldStyle(.plain).focused($searchFocused)
                if !model.messageQuery.isEmpty {
                    Button { model.messageQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }.padding()
            Divider()
            }
            HistoryMessageList(model: model, padding: compact ? 10 : 20) {
                        if model.messages.items.isEmpty {
                            ContentUnavailableView(model.messageQuery.isEmpty ? "从一条消息开始" : "没有找到相关内容", systemImage: "text.bubble", description: Text(model.messageQuery.isEmpty ? "发送文字、图片或文件，其他设备会同步显示。" : "试试其他关键词。"))
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(orderedMessages.enumerated()), id: \.element.id) { index, message in
                            if MessagePresentation.startsDay(message.createdAt, previous: index > 0 ? orderedMessages[index - 1].createdAt : nil) {
                                // Keep the date marker consistent with the web and Flutter clients:
                                // a compact, translucent muted pill with generous separation from
                                // the message groups. A white fill made the marker look like a
                                // message bubble on the tinted chat background.
                                Text(MessagePresentation.dayLabel(message.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundStyle(ChatStyle.muted)
                                    .lineSpacing(1.4)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 4)
                                    .background(ChatStyle.muted.opacity(0.19), in: Capsule())
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 10)
                                    .padding(.bottom, 17)
                            }
                            MessageCard(message: message, model: model, query: model.messageQuery, copied: copiedID == message.id, copy: {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                #else
                                UIPasteboard.general.string = message.content
                                #endif
                                copiedID = message.id
                            }, annotate: { annotatingMessage = message }, star: { Task { await model.toggleStar(message) } }, delete: { deletingMessage = message })
                            .id(message.id)
                        }
            }.id(model.historyKey)
            .background(ChatStyle.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                if let data = model.imageDrafts[conversation.id], let image = platformImage(data) {
                    HStack {
                        image.resizable().scaledToFit().frame(width: 80, height: 70)
                        Text("图片待发送").font(.caption)
                        Spacer()
                        Button { model.imageDrafts.removeValue(forKey: conversation.id) } label: { Label("移除图片", systemImage: "xmark.circle") }.disabled(model.sending)
                    }
                }
                if let files = model.fileDrafts[conversation.id], !files.isEmpty {
                    ScrollView { VStack(spacing: 4) {
                        ForEach(files) { file in HStack {
                            Label(file.name, systemImage: "paperclip").font(.caption).lineLimit(1)
                            Spacer()
                            Button { model.fileDrafts[conversation.id]?.removeAll { $0.id == file.id } } label: { Label("移除附件", systemImage: "xmark") }.labelStyle(.iconOnly).disabled(model.sending)
                        } }
                    } }.frame(maxHeight: 100)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Menu {
                        Button { choosingFiles = true } label: { Label("文件", systemImage: "folder") }.disabled(model.imageDrafts[conversation.id] != nil)
                        Button { choosingImage = true } label: { Label("图片", systemImage: "photo") }.disabled(model.imageDrafts[conversation.id] != nil || !(model.fileDrafts[conversation.id] ?? []).isEmpty)
                        #if os(iOS)
                        PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) { Label("照片图库", systemImage: "photo.on.rectangle") }
                            .disabled(model.imageDrafts[conversation.id] != nil || !(model.fileDrafts[conversation.id] ?? []).isEmpty)
                        #endif
                        Text("最多 5 个附件，合计 20 MB")
                    } label: { Image(systemName: "paperclip").font(.title3).frame(width: 36, height: 40) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(model.sending).accessibilityLabel("添加附件")
                        #if os(macOS)
                        .menuIndicator(.hidden)
                        #endif
                TextField("输入消息…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.plain)
                    #if os(macOS)
                    .onPasteCommand(of: [.image]) { pasteImages($0) }
                    .onKeyPress(.return, phases: .down) { press in
                        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
                        // Candidate confirmation belongs to the input method, not message sending.
                        if editor?.hasMarkedText() == true { return .ignored }
                        guard press.modifiers.intersection([.option, .control, .command]).isEmpty else {
                            return .ignored
                        }
                        if press.modifiers.contains(.shift) {
                            // SwiftUI's field editor otherwise commits/selects the text on Shift+Return.
                            guard let editor else { return .ignored }
                            editor.insertNewlineIgnoringFieldEditor(nil)
                            return .handled
                        }
                        if model.canSend { Task { await model.send() } }
                        return .handled
                    }
                    #endif
                    .padding(.vertical, 10).disabled(model.sending)
                    Button { Task { await model.send() } } label: {
                        Image(systemName: "paperplane.fill").frame(width: 22, height: 28)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.circle).disabled(!model.canSend)
                        .accessibilityLabel(model.sending ? "发送中" : "发送").help(composerHint)
                        .keyboardShortcut(.return, modifiers: .command)
                }.padding(6).background(.white, in: RoundedRectangle(cornerRadius: 18))
                if model.draft.count > 50_000 { Text("正文最多 50,000 字").font(.caption).foregroundStyle(.red) }
            }.padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(ChatStyle.ink).background(ChatStyle.background)
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                var files = model.fileDrafts[conversation.id] ?? []
                guard files.count + urls.count <= 5 else { throw APIError(message: "最多选择 5 个附件") }
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size + files.reduce(0, { $0 + $1.data.count }) <= 20 * 1024 * 1024 else { throw APIError(message: "请选择非空文件，合计不超过 20 MB") }
                    let data = try Data(contentsOf: url)
                    guard !data.isEmpty, data.count + files.reduce(0, { $0 + $1.data.count }) <= 20 * 1024 * 1024 else { throw APIError(message: "附件合计不能超过 20 MB") }
                    files.append(PendingFile(name: url.lastPathComponent, data: data))
                }
                model.fileDrafts[conversation.id] = files
            } catch { model.error = userFacingError(error) }
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { throw APIError(message: "图片不能超过 8 MB") }
                model.imageDrafts[conversation.id] = try prepareImage(Data(contentsOf: url))
            } catch { model.error = userFacingError(error) }
        }
        #if os(iOS)
        .onChange(of: photo) { _, item in
            let id = conversation.id
            Task {
                do { if let data = try await item?.loadTransferable(type: Data.self) { model.imageDrafts[id] = try prepareImage(data) } }
                catch { model.error = userFacingError(error) }
                photo = nil
            }
        }
        #endif
        .sheet(item: $annotatingMessage) { message in
            AnnotationEditor(message: message, model: model)
        }
        .navigationTitle(compact ? "" : conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .onExitCommand {
            if searchOpen { searchOpen = false; model.messageQuery = "" }
        }
        #endif
        .toolbar {
          if !compact {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    searchOpen.toggle()
                    if searchOpen { searchFocused = true } else { model.messageQuery = "" }
                } label: { Label(searchOpen ? "收起搜索" : "搜索消息", systemImage: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(conversation.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") { Task { await model.togglePin(conversation) } }
                    Button("重命名", systemImage: "pencil", action: rename)
                    Button("刷新消息", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    Button("删除会话", systemImage: "trash", role: .destructive, action: delete)
                } label: { Label("会话操作", systemImage: "ellipsis.circle") }
                #if os(macOS)
                .menuIndicator(.hidden)
                #endif
            }
          }
        }
        .task(id: model.messageQuery) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            model.messagePage = 1
            await model.loadMessages()
        }
        .alert("删除这条消息？", isPresented: Binding(get: { deletingMessage != nil }, set: { if !$0 { deletingMessage = nil } })) {
            Button("取消", role: .cancel) { deletingMessage = nil }
            Button("删除", role: .destructive) {
                if let message = deletingMessage { Task { await model.deleteMessage(message) } }
                deletingMessage = nil
            }
        } message: { Text("消息会从所有设备永久删除。") }
    }

    private var composerHint: String {
        #if os(macOS)
        "Enter 发送 · Shift+Enter 换行"
        #else
        "最多 5 个附件 · 合计 20 MB"
        #endif
    }

    #if os(macOS)
    private func pasteImages(_ providers: [NSItemProvider]) {
        guard !model.sending else { return }
        let id = conversation.id
        guard providers.count == 1, let provider = providers.first,
              let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            model.error = "请一次粘贴一张图片"
            return
        }
        guard model.imageDrafts[id] == nil, (model.fileDrafts[id] ?? []).isEmpty else {
            model.error = "请先发送或移除待发送的附件"
            return
        }
        Task { @MainActor in
            do {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? APIError(message: "无法读取剪贴板图片")) }
                    }
                }
                guard !model.sending, model.selected?.id == id,
                      model.imageDrafts[id] == nil, (model.fileDrafts[id] ?? []).isEmpty else { return }
                model.imageDrafts[id] = try prepareImage(data)
            } catch { model.error = userFacingError(error, fallback: "无法粘贴图片，请重试") }
        }
    }
    #endif
}

private struct HistoryEdges: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct HistoryMessageList<Content: View>: View {
    let model: WorkspaceModel
    var padding: CGFloat = 20
    @ViewBuilder let content: () -> Content
    @State private var initialized = false
    private var history: MessageHistory { model.messageHistory }
    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if history.loadingOlder || history.olderError != nil || history.hasOlder {
                            HStack {
                                Spacer()
                                if history.loadingOlder { Text("正在加载更早消息…") }
                                else if history.olderError != nil {
                                    Button("加载失败，点击重试") { Task { await model.loadOlderMessages() } }
                                } else { Text("向上滚动查看更早消息") }
                                Spacer()
                            }.font(.caption).foregroundStyle(.secondary).frame(height: 28)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: HistoryEdges.self, value: ["top": geometry.frame(in: .named("history")).minY])
                                })
                        }
                        content()
                        Color.clear.frame(height: 1).id("bottom")
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: HistoryEdges.self, value: ["bottom": geometry.frame(in: .named("history")).maxY])
                            })
                    }.scrollTargetLayout().padding(padding).frame(maxWidth: 880).frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "history")
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: Binding(get: { history.positionID }, set: { history.positionID = $0 }), anchor: .top)
                .onPreferenceChange(HistoryEdges.self) { edges in
                    guard initialized else { return }
                    if let bottom = edges["bottom"] { history.atBottom = bottom <= viewport.size.height + 64 && bottom > 0 }
                    else { history.atBottom = false }
                    if let top = edges["top"], top > -120, top < viewport.size.height,
                       history.hasOlder, !history.loadingOlder, history.olderError == nil {
                        Task { await model.loadOlderMessages() }
                    }
                }
                .onAppear { restore(proxy) }
                .onChange(of: model.messages.items.first?.id) { old, _ in
                    if !initialized { restore(proxy) }
                    else if old != nil && history.atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: model.scrollToLatest) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .overlay(alignment: .bottomTrailing) {
                    if initialized && !history.atBottom && !model.messages.items.isEmpty {
                        Button { proxy.scrollTo("bottom", anchor: .bottom) } label: { Label("回到底部", systemImage: "arrow.down") }
                            .buttonStyle(.bordered).padding(12)
                    }
                }
            }
        }
    }
    private func restore(_ proxy: ScrollViewProxy) {
        guard !model.messages.items.isEmpty else { return }
        if !history.atBottom, let id = history.positionID { proxy.scrollTo(id, anchor: .top) }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
        initialized = true
    }
}

struct MessageCard: View {
    let message: Message
    let model: WorkspaceModel
    var query = ""
    var showDate = false
    let copied: Bool
    let copy: () -> Void
    let annotate: () -> Void
    @State private var expandedNote = false
    @State private var hovered = false
    let star: () -> Void
    let delete: () -> Void
    private var own: Bool { model.currentDeviceId != nil && message.senderDevice?.id == model.currentDeviceId }
    private var menuButtonSize: CGSize {
        #if os(macOS)
        CGSize(width: 30, height: 36)
        #else
        CGSize(width: 44, height: 44)
        #endif
    }
    private var menuSpace: CGFloat { menuButtonSize.width + 4 }
    private var hasBody: Bool {
        if message.image != nil && message.content == "[图片]" { return false }
        if let files = message.attachments, !files.isEmpty && message.content == "[附件] " + files.map(\.name).joined(separator: "、") { return false }
        return true
    }
    private var timestamp: String {
        guard let date = MessagePresentation.date(message.createdAt) else { return message.createdAt }
        return date.formatted(date: showDate ? .abbreviated : .omitted, time: .shortened)
    }
    private var menuActions: [MessageMenuAction] {
        [
            MessageMenuAction(id: "copy", title: copied ? "已复制" : "复制内容", symbol: copied ? "checkmark" : "doc.on.doc", perform: copy),
            MessageMenuAction(id: "star", title: message.isStarred ? "取消收藏" : "收藏", symbol: message.isStarred ? "star.fill" : "star", perform: star),
            MessageMenuAction(id: "annotate", title: (message.annotation ?? "").isEmpty ? "添加批注" : "编辑批注", symbol: "text.bubble", perform: annotate),
            MessageMenuAction(id: "delete", title: "删除消息", symbol: "trash", destructive: true, perform: delete)
        ]
    }
    private var actions: some View {
        ForEach(menuActions) { action in
            Button(role: action.destructive ? .destructive : nil, action: action.perform) {
                Label(action.title, systemImage: action.symbol)
            }
        }
    }
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if own { Spacer(minLength: 24) }
            VStack(alignment: .trailing, spacing: 5) {
              VStack(alignment: .leading, spacing: 5) {
                Text(message.senderDevice?.name ?? "未登记设备").font(.caption2).fontWeight(own ? .semibold : .medium)
                    .foregroundStyle(own ? ChatStyle.blue : ChatStyle.muted).lineLimit(1)
                if message.filesExpired == true { Label("图片已清理", systemImage: "photo").font(.caption).foregroundStyle(ChatStyle.muted) }
                ForEach(message.attachments ?? []) { file in AttachmentView(message: message, file: file, model: model, query: query) }
                if message.image != nil { ImageMessageView(messageID: message.id, model: model) }
                if hasBody { HighlightedText(text: message.content, query: query, links: true).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if let note = message.annotation, !note.isEmpty {
                    let matched = !MessagePresentation.matches(note, query: query).isEmpty
                    let longNote = note.count > 140 || note.split(separator: "\n", omittingEmptySubsequences: false).count > 4
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: annotate) { Label("批注", systemImage: "text.bubble") }.buttonStyle(.plain).font(.caption2).foregroundStyle(ChatStyle.muted)
                        HighlightedText(text: note, query: query).font(.callout).textSelection(.enabled).lineLimit(expandedNote || matched || !longNote ? nil : 4)
                        if longNote && !matched { Button(expandedNote ? "收起" : "展开批注") { expandedNote.toggle() }.buttonStyle(.plain).font(.caption) }
                    }.padding(10).background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .leading) { Rectangle().fill(ChatStyle.blue.opacity(0.35)).frame(width: 2) }
                }
              }
                HStack(spacing: 4) {
                    if copied { Text("已复制").foregroundStyle(ChatStyle.blue) }
                    if message.isStarred { Image(systemName: "star.fill").foregroundStyle(.orange) }
                    Text(timestamp).foregroundStyle(ChatStyle.muted)
                }.font(.system(size: 10))
            }.padding(10).background(own ? ChatStyle.outgoing : .white, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(ChatStyle.ink)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                #if os(macOS)
                .overlay {
                    MessageSecondaryClickMenu(actions: menuActions, disabled: model.mutating)
                        .accessibilityHidden(true)
                }
                #else
                .contextMenu { actions.disabled(model.mutating) }
                #endif
                // Anchor actions to the visible bubble, before the flexible row frame.
                .overlay(alignment: own ? .leading : .trailing) {
                    more.offset(x: own ? -menuSpace : menuSpace)
                }
                .padding(own ? .leading : .trailing, menuSpace)
                .frame(maxWidth: 640 + menuSpace, alignment: own ? .trailing : .leading)
            if !own { Spacer(minLength: 24) }
        }.onHover { hovered = $0 }
    }
    private var more: some View {
        Menu { actions.disabled(model.mutating) } label: {
            Image(systemName: "ellipsis")
                .frame(width: menuButtonSize.width, height: menuButtonSize.height)
        }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多消息操作")
            #if os(macOS)
            .menuIndicator(.hidden)
            .opacity(hovered ? 1 : 0.15)
            #endif
    }
}

struct AnnotationEditor: View {
    let message: Message
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool
    init(message: Message, model: WorkspaceModel) {
        self.message = message
        self.model = model
        _text = State(initialValue: message.annotation ?? "")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text((message.annotation ?? "").isEmpty ? "添加批注" : "编辑批注").font(.headline)
                Text(verbatim: message.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                TextEditor(text: $text).focused($focused).frame(height: 160).padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("批注").disabled(saving)
                HStack { Text("所有设备可见，可通过搜索找到"); Spacer(); Text("\(text.unicodeScalars.count) / 2000") }
                    .font(.caption2).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if !(message.annotation ?? "").isEmpty {
                    Button("删除批注", role: .destructive) { confirmingDelete = true }.disabled(saving)
                }
                HStack {
                    Spacer()
                    Button("取消") { dismiss() }.disabled(saving)
                    Button(saving ? "保存中…" : "保存批注") { save(text) }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 2000 || text == (message.annotation ?? ""))
                }
            }.padding(24)
        }
        .frame(idealWidth: 460, idealHeight: 420)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
        .interactiveDismissDisabled(saving)
        .onAppear { focused = true }
        .alert("删除批注？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("删除批注", role: .destructive) { save("") }
        } message: { Text("消息和附件会保留，批注会从所有设备移除。") }
    }
    private func save(_ value: String) {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            do { try await model.saveAnnotation(message, text: value); dismiss() }
            catch { self.error = userFacingError(error) }
            saving = false
        }
    }
}
