import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct FavoritesView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var annotating: Message?
    @State private var deleting: Message?
    @State private var copiedID: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("搜索正文、批注或文件名", text: $model.favoriteQuery).textFieldStyle(.roundedBorder).padding()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if model.favorites.items.isEmpty { ContentUnavailableView(model.favoriteQuery.isEmpty ? "暂无收藏" : "没有匹配的收藏", systemImage: "star", description: Text("收藏重要内容，方便下次查找。")) }
                        ForEach(model.favorites.items) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { Task { if await model.openConversation(message) { dismiss() } } } label: { HStack { HighlightedText(text: message.conversationTitle ?? "查看所属会话", query: model.favoriteQuery); Image(systemName: "arrow.up.forward") }.lineLimit(1).font(.caption) }.buttonStyle(.plain).foregroundStyle(.tint)
                                MessageCard(message: message, model: model, query: model.favoriteQuery, showDate: true, copied: copiedID == message.id, copy: {
                                    #if os(macOS)
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string)
                                    #else
                                    UIPasteboard.general.string = message.content
                                    #endif
                                    copiedID = message.id
                                }, annotate: { annotating = message }, star: { Task { await model.toggleStar(message) } }, delete: { deleting = message })
                            }
                        }
                    }.padding()
                }
                PageControls(page: model.favoritePage, totalPages: model.favorites.totalPages) { page in model.favoritePage = page; Task { await model.loadFavorites() } }
            }.navigationTitle("收藏")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.frame(idealWidth: 650, idealHeight: 650)
            .task { while !Task.isCancelled { await model.loadFavorites(); do { try await Task.sleep(for: .seconds(5)) } catch { return } } }
            .task(id: model.favoriteQuery) { do { try await Task.sleep(for: .milliseconds(350)) } catch { return }; model.favoritePage = 1; await model.loadFavorites() }
            .sheet(item: $annotating) { AnnotationEditor(message: $0, model: model) }
            .alert("删除这条消息？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) { if let message = deleting { Task { await model.deleteMessage(message) } }; deleting = nil }
            } message: { Text("消息和附件将从所有设备永久删除。") }
    }
}
