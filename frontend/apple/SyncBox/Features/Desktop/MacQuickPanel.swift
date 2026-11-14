#if os(macOS)
import AppKit
import SwiftUI

struct MacQuickPanel: View {
    @Bindable var connection: ConnectionModel
    private let onOpenMainWindow: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    @State private var restoring = true

    init(connection: ConnectionModel, onOpenMainWindow: (() -> Void)? = nil) {
        self.connection = connection
        self.onOpenMainWindow = onOpenMainWindow
    }

    var body: some View {
        Group {
            if connection.stage == .workspace, let workspace = connection.workspace {
                MacQuickWorkspacePanel(model: workspace, connection: connection, onOpenMainWindow: onOpenMainWindow)
            } else {
                VStack(spacing: 16) {
                    Image("BrandIcon").resizable().scaledToFit().frame(width: 48, height: 48)
                    Text("SyncBox").font(.title2.bold())
                    if restoring {
                        ProgressView("正在连接…").controlSize(.small)
                    } else {
                        Text(connection.error ?? "连接你的服务，开始收发内容。")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("打开并登录") {
                            openMainWindow()
                        }.buttonStyle(.borderedProminent)
                    }
                    Button("退出 SyncBox") { NSApp.terminate(nil) }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 380, height: 560)
        .task { await connection.restore(); restoring = false }
    }

    private func openMainWindow() {
        if let onOpenMainWindow {
            onOpenMainWindow()
        } else {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct MacQuickWorkspacePanel: View {
    @Bindable var model: WorkspaceModel
    @Bindable var connection: ConnectionModel
    private let onOpenMainWindow: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    @State private var creating = false
    @State private var title = ""
    @State private var editing: Conversation?
    @State private var deleting: Conversation?
    @State private var showSettings = false
    @State private var settingsLocked = false

    init(model: WorkspaceModel, connection: ConnectionModel, onOpenMainWindow: (() -> Void)? = nil) {
        self.model = model
        self.connection = connection
        self.onOpenMainWindow = onOpenMainWindow
    }

    var body: some View {
        VStack(spacing: 0) {
          Group {
            if let conversation = model.selected {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button {
                            model.selected = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .help("返回消息列表")
                        .accessibilityLabel("返回消息列表")
                        Text(conversation.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Menu {
                            Button(conversation.isPinned == true ? "取消置顶" : "置顶") { Task { await model.togglePin(conversation) } }
                            Button("重命名") { editing = conversation; title = conversation.title; creating = true }
                            Button("删除会话", role: .destructive) { deleting = conversation }
                        } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(model.mutating).accessibilityLabel("会话操作")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    Divider()
                    ConversationDetailView(
                        model: model,
                        conversation: conversation,
                        rename: { editing = conversation; title = conversation.title; creating = true },
                        delete: { deleting = conversation },
                        compact: true
                    )
                }
            } else {
                conversationList
            }
          }
          if let error = model.error {
              HStack(alignment: .top) {
                  Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                  Button { model.error = nil } label: { Image(systemName: "xmark") }
                      .buttonStyle(.plain).accessibilityLabel("关闭提示")
              }.padding(10)
          }
          Divider()
          footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.refresh()
        }
        .task(id: model.conversationQuery) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            model.conversationPage = 1
            await model.loadConversations()
        }
        .task(id: model.selected?.id) {
            guard model.selected != nil else { return }
            await model.loadMessages()
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 14) {
                Text(editing == nil ? "新建会话" : "重命名会话").font(.headline)
                TextField("会话名称", text: $title)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { creating = false }
                    Button("保存") {
                        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        Task {
                            if await model.saveConversation(title: value, editing: editing) {
                                creating = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.mutating || !(1...80).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(connection: connection, model: model, onNavigationLockChanged: { settingsLocked = $0 })
        }
        .alert("删除会话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let conversation = deleting { Task { await model.deleteConversation(conversation) } }
                deleting = nil
            }
        } message: { Text("会话中的消息和附件将从所有设备永久删除。") }
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("消息列表").font(.headline)
                Spacer()
                Button {
                    editing = nil
                    title = "新建会话" + Self.dateFormatter.string(from: Date())
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建会话")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索会话或内容", text: $model.conversationQuery)
                    .textFieldStyle(.plain)
                if !model.conversationQuery.isEmpty {
                    Button { model.conversationQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Divider()
            if model.conversations.items.isEmpty {
                ContentUnavailableView {
                    Label(model.loading ? "正在加载…" : model.conversationQuery.isEmpty ? "暂无会话" : "没有匹配的会话", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(model.conversationQuery.isEmpty ? "新建会话，开始发送内容。" : "换个关键词试试。")
                } actions: {
                    if model.conversationQuery.isEmpty {
                        Button("新建会话") { editing = nil; title = "新建会话" + Self.dateFormatter.string(from: Date()); creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List(model.conversations.items) { conversation in
                    Button {
                        model.selected = conversation
                    } label: {
                        ConversationRow(conversation: conversation, query: model.conversationQuery)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(conversation.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") {
                            Task { await model.togglePin(conversation) }
                        }
                        Button("重命名", systemImage: "pencil") {
                            editing = conversation
                            title = conversation.title
                            creating = true
                        }
                        Button("删除会话", systemImage: "trash", role: .destructive) {
                            deleting = conversation
                        }
                    }
                    .disabled(model.mutating)
                }
                .listStyle(.plain)
            }
            PageControls(page: model.conversationPage, totalPages: model.conversations.totalPages) { page in
                model.conversationPage = page
                Task { await model.loadConversations() }
            }
        }
    }

    private var footer: some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(model.realtimeConnected ? .green : .orange)
                    .frame(width: 7, height: 7)
                    .help(model.realtimeConnected ? "实时同步" : "定时同步")
                Text(connection.username).lineLimit(1)
                Spacer()
                Menu {
                    Button("设置…") { showSettings = true }
                    Button("刷新") { Task { await model.refresh() } }
                    Divider()
                    Button("退出 SyncBox") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(settingsLocked).accessibilityLabel("设置与退出")
                Button("打开完整窗口", systemImage: "macwindow") { showMainWindow() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("打开完整窗口")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
    }

    private func showMainWindow() {
        if let onOpenMainWindow {
            onOpenMainWindow()
        } else {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        return formatter
    }()
}
#endif
