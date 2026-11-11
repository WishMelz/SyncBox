import SwiftUI

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @Bindable var connection: ConnectionModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif
    @State private var titleEditor: ConversationEditRequest?
    @State private var deleting: Conversation?
    @State private var showDevices = false
    @State private var showLogout = false
    @State private var showFavorites = false
    @State private var showSettings = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = 0
    @State private var settingsLocked = false
    #endif

    var body: some View {
        workspace
        .task(id: scenePhase) {
            guard scenePhase == .active else { model.stopEvents(); return }
            model.startEvents()
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(model.realtimeConnected ? 30 : 5)) } catch { return }
            }
        }
        .onDisappear { model.stopEvents() }
        .task(id: model.selected?.id) { await model.loadMessages() }
        .task(id: model.conversationQuery) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            model.conversationPage = 1
            await model.loadConversations()
        }
        .sheet(item: $titleEditor) { request in
            ConversationTitleEditor(model: model, conversation: request.conversation)
        }
        .sheet(isPresented: $showFavorites) { FavoritesView(model: model) }
        .sheet(isPresented: $showSettings) { SettingsView(connection: connection, model: model) }
        .sheet(isPresented: $showDevices) { DevicesView(model: model, server: connection.serverText, currentDeviceId: connection.deviceId) }
        .alert("删除会话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let conversation = deleting { Task { await model.deleteConversation(conversation) } }
                deleting = nil
            }
        } message: { Text("“\(deleting?.title ?? "")”和其中的全部消息将从所有设备永久删除。") }
        .alert("退出登录？", isPresented: $showLogout) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { Task { await connection.logout() } }
        } message: { Text("将撤销本设备当前登录，未发送的草稿不会保留。") }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    @ViewBuilder private var workspace: some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            mobileTabs.tabViewStyle(.tabBarOnly)
        } else {
            mobileTabs
        }
        #else
        messagesWorkspace
        #endif
    }

    #if os(iOS)
    // The system tab bar supplies Liquid Glass on iOS 26+, and native blur on
    // earlier supported versions, including safe areas and accessibility.
    private var mobileTabs: some View {
        TabView(selection: Binding(get: { selectedTab }, set: { if !settingsLocked { selectedTab = $0 } })) {
            messagesWorkspace
                .tabItem { Label("消息", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            SettingsView(connection: connection, model: model, embedded: true,
                         onNavigationLockChanged: { settingsLocked = $0 })
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(1)
        }
    }
    #endif

    private func conversationMenuColor(_ conversation: Conversation) -> Color {
        #if os(macOS)
        if model.selected?.id == conversation.id && controlActiveState != .inactive { return .white }
        #endif
        return ChatStyle.blue
    }

    private var messagesWorkspace: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索会话或内容", text: $model.conversationQuery)
                        .textFieldStyle(.plain)
                    if !model.conversationQuery.isEmpty {
                        Button { model.conversationQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                }.padding(12)
                Button { showFavorites = true } label: { Label("收藏", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
                List(selection: $model.selected) {
                    ForEach(model.conversations.items) { conversation in
                        NavigationLink(value: conversation) {
                            HStack {
                                ConversationRow(conversation: conversation, query: model.conversationQuery)
                                Menu {
                                    Button(conversation.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") { Task { await model.togglePin(conversation) } }
                                    Button("重命名", systemImage: "pencil") { edit(conversation) }
                                    Button("删除会话", systemImage: "trash", role: .destructive) { deleting = conversation }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        #if os(macOS)
                                        .foregroundStyle(conversationMenuColor(conversation))
                                        .frame(minWidth: 32, minHeight: 32)
                                        #else
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        #endif
                                }
                                .menuStyle(.borderlessButton).fixedSize().disabled(model.mutating)
                                .accessibilityLabel("会话操作")
                                #if os(macOS)
                                .tint(conversationMenuColor(conversation))
                                .menuIndicator(.hidden)
                                #endif
                            }
                        }
                        .contextMenu {
                            Button(conversation.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") { Task { await model.togglePin(conversation) } }
                            Button("重命名", systemImage: "pencil") { edit(conversation) }
                            Button("删除会话", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                    }
                }
                .refreshable { await model.refresh() }
                .overlay {
                    if model.conversations.items.isEmpty {
                        ContentUnavailableView(model.loading ? "正在加载…" : model.conversationQuery.isEmpty ? "暂无会话" : "没有匹配的会话", systemImage: "bubble.left.and.bubble.right", description: Text(model.conversationQuery.isEmpty ? "新建会话，分享文字、图片或文件。" : "换个关键词试试。"))
                            .allowsHitTesting(false)
                    }
                }
                PageControls(page: model.conversationPage, totalPages: model.conversations.totalPages) { page in
                    model.conversationPage = page
                    Task { await model.loadConversations() }
                }
                #if os(macOS)
                HStack {
                    Circle().fill(model.error == nil ? .green : .orange).frame(width: 6, height: 6).accessibilityLabel(model.error == nil ? "已同步" : "连接中断")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.username).lineLimit(1)
                        Text(model.error != nil ? "连接中断" : model.lastSynced == nil ? "正在连接…" : model.realtimeConnected ? "实时同步" : "定时同步").font(.caption2)
                    }
                    Spacer()
                    Menu {
                        Button("设置", systemImage: "gearshape") { showSettings = true }
                        Button("已登记设备", systemImage: "desktopcomputer") { showDevices = true }
                        Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right") { showLogout = true }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .menuIndicator(.hidden)
                    .accessibilityLabel("账号与设置")
                }.font(.caption).foregroundStyle(.secondary).padding()
                #endif
            }
            #if os(iOS)
            .navigationTitle("消息列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .tabBar)
            #else
            .navigationTitle("SyncBox")
            #endif
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { edit(nil) } label: {
                        #if os(iOS)
                        Label("新建会话", systemImage: "plus")
                        #else
                        Label("新建会话", systemImage: "square.and.pencil")
                        #endif
                    }
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
        } detail: {
            if let conversation = model.selected {
                ConversationDetailView(model: model, conversation: conversation, rename: { edit(conversation) }, delete: { deleting = conversation })
                    #if os(iOS)
                    .toolbar(horizontalSizeClass == .compact ? .hidden : .visible, for: .tabBar)
                    #endif
            } else {
                ContentUnavailableView {
                    Label("让内容自由流动", systemImage: "square.stack.3d.up")
                } description: { Text("选择或新建会话，发送到你的所有设备。") } actions: {
                    Button("新建会话") { edit(nil) }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
    private func edit(_ conversation: Conversation?) {
        titleEditor = ConversationEditRequest(conversation: conversation)
    }
}

private struct ConversationEditRequest: Identifiable {
    let id = UUID()
    let conversation: Conversation?
}

private struct ConversationTitleEditor: View {
    @Bindable var model: WorkspaceModel
    let conversation: Conversation?
    @State private var title: String
    @Environment(\.dismiss) private var dismiss

    init(model: WorkspaceModel, conversation: Conversation?) {
        self.model = model
        self.conversation = conversation
        let formatter = DateFormatter(); formatter.dateFormat = "yyMMdd"
        _title = State(initialValue: conversation?.title ?? "新建会话" + formatter.string(from: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(conversation == nil ? "新建会话" : "重命名会话").font(.title2.bold())
            Text("将相关内容放在一起，例如灵感、链接或临时传输。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("会话名称（1–80 个字符）", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    Task { if await model.saveConversation(title: title, editing: conversation) { dismiss() } }
                }.buttonStyle(.borderedProminent)
                    .disabled(model.mutating || !(1...80).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count))
            }
        }.padding(24).frame(idealWidth: 420).presentationDetents([.medium])
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var query = ""
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if conversation.isPinned == true { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HighlightedText(text: conversation.title, query: query).font(.headline).lineLimit(1)
                    Spacer()
                }
                HighlightedText(text: conversation.preview ?? "还没有消息", query: query).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 6)
    }
}

struct PageControls: View {
    let page: Int
    let totalPages: Int
    let change: (Int) -> Void
    var body: some View {
        if totalPages > 1 || page > 1 {
            HStack {
                Button { change(page - 1) } label: { Label("上一页", systemImage: "chevron.left") }.disabled(page <= 1)
                Spacer()
                Text("\(page) / \(max(1, totalPages))").font(.caption).monospacedDigit()
                Spacer()
                Button { change(page + 1) } label: { Label("下一页", systemImage: "chevron.right") }.disabled(page >= totalPages)
            }.buttonStyle(.borderless).labelStyle(.iconOnly).padding(12)
        }
    }
}

struct DevicesView: View {
    @Bindable var model: WorkspaceModel
    let server: String
    let currentDeviceId: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("服务地址") { Text(server).textSelection(.enabled) }
                Section("已登记设备") {
                    ForEach(model.devices) { device in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(device.name)
                                    if device.id == currentDeviceId {
                                        Text("当前设备").font(.caption).foregroundStyle(.tint)
                                    }
                                }
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill((device.online ?? false) ? Color.green : Color.secondary)
                                        .frame(width: 7, height: 7)
                                    Text(device.platform + " · " + ((device.online ?? false) ? "在线" : "离线"))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Text(device.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        } icon: {
                            Image(systemName: ["macos", "windows", "linux"].contains(device.platform) ? "desktopcomputer" : "iphone")
                        }
                    }
                }
                Section { Text("在线状态按最近 90 秒内的活动判断。内容每 5 秒在前台刷新。")
                    .font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("我的设备")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task { await model.loadDevices() }
        }.frame(idealWidth: 460, idealHeight: 500)
    }
}
