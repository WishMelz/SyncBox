import SwiftUI

private struct HistoryEdges: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct HistoryLoaderFrame: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let frame = nextValue()
        if !frame.isNull { value = frame }
    }
}

@MainActor
private final class HistoryScrollCommands {
    var jump: Task<Void, Never>?
    func cancel() { jump?.cancel(); jump = nil }
}

struct HistoryMessageList<Content: View>: View {
    let model: WorkspaceModel
    var padding: CGFloat = 20
    @ViewBuilder let content: () -> Content
    @State private var initialized = false
    @State private var commands = HistoryScrollCommands()
    private var history: MessageHistory { model.messageHistory }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                let history = history
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if history.loadingOlder || history.olderError != nil || history.hasOlder {
                            HistoryOlderLoader(history: history, viewportHeight: viewport.size.height) {
                                await model.loadOlderMessages()
                            }
                        }
                        content()
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .scrollTargetLayout()
                    .padding(padding)
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
                    .background(GeometryReader { geometry in
                        // Measure the container: a lazy bottom sentinel can
                        // disappear during scrolling and report a false edge.
                        Color.clear.preference(key: HistoryEdges.self, value: geometry.frame(in: .named("history")))
                    })
                }
                .coordinateSpace(name: "history")
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: Binding(
                    get: { history.positionID },
                    set: { history.positionID = $0 }
                ), anchor: .top)
                .onPreferenceChange(HistoryEdges.self) { frame in
                    guard initialized, !frame.isNull else { return }
                    history.updateBottomDistance(frame.maxY - viewport.size.height)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in commands.cancel() })
                .onAppear { restore(proxy) }
                .onDisappear { commands.cancel() }
                .onChange(of: model.messages.items.first?.id) { old, _ in
                    if !initialized { restore(proxy) }
                    else if old != nil && history.atBottom { scrollToBottom(proxy) }
                }
                .onChange(of: model.scrollToLatest) { _, _ in scrollToBottom(proxy) }
                .overlay(alignment: .bottomTrailing) {
                    // Only this child observes atBottom while rendering. Showing
                    // the control must not invalidate the lazy list's content.
                    HistoryBottomButton(history: history, enabled: initialized && !model.messages.items.isEmpty) {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private func restore(_ proxy: ScrollViewProxy) {
        guard !model.messages.items.isEmpty else { return }
        if !history.atBottom, let id = history.positionID { proxy.scrollTo(id, anchor: .top) }
        else { scrollToBottom(proxy) }
        initialized = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        commands.cancel()
        let history = history
        history.positionID = nil
        history.atBottom = true
        proxy.scrollTo("bottom", anchor: .bottom)
        // A long lazy stack can refine its estimated height after the first
        // jump. Corrections are explicit and stop as soon as the user drags.
        commands.jump = Task { @MainActor in
            for _ in 0..<2 {
                await Task.yield()
                guard !Task.isCancelled else { return }
                history.positionID = nil
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

/// The lazy stack's estimated origin can differ from the first row's actual
/// position. Observe the loader itself and re-check after a page finishes, even
/// if the finger has stopped moving and no new scroll event is delivered.
private struct HistoryOlderLoader: View {
    let history: MessageHistory
    let viewportHeight: CGFloat
    let load: () async -> Void
    @State private var nearTop = false

    private var requestCursor: String? {
        guard nearTop, history.ready, history.hasOlder,
              !history.loadingOlder, history.olderError == nil else { return nil }
        return history.page.items.last.map(MessageHistory.cursor)
    }

    var body: some View {
        HStack {
            Spacer()
            if history.loadingOlder { Text("正在加载更早消息…") }
            else {
                Button(history.olderError == nil ? "加载更早消息" : "加载失败，点击重试") {
                    Task { await load() }
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(height: 28)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: HistoryLoaderFrame.self, value: geometry.frame(in: .named("history")))
        })
        .onPreferenceChange(HistoryLoaderFrame.self) { frame in
            let visible = !frame.isNull && frame.maxY >= -120 && frame.minY <= viewportHeight + 120
            if visible != nearTop { nearTop = visible }
        }
        .onDisappear { nearTop = false }
        .onChange(of: requestCursor, initial: true) { _, cursor in
            guard cursor != nil else { return }
            // Do not tie cancellation to loadingOlder: setting that flag would
            // cancel a .task(id:) while its network request is in flight.
            Task { await load() }
        }
    }
}

private struct HistoryBottomButton: View {
    let history: MessageHistory
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        let visible = enabled && !history.atBottom
        Button(action: action) { Label("回到底部", systemImage: "arrow.down") }
            .buttonStyle(.bordered)
            .padding(12)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
