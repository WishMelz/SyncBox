import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: FileItem?
    @State private var document: AttachmentDocument?
    @State private var exportingFilename = "attachment"
    @State private var exporting = false
    @State private var savingID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField("搜索文件名或会话名称", text: $model.fileQuery)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("分类", selection: $model.fileCategory) {
                            Text("全部").tag("all")
                            Text("图片").tag("image")
                            Text("文件").tag("file")
                        }
                        .pickerStyle(.segmented)
                        Picker("排序", selection: $model.fileSort) {
                            Text("最新").tag("newest")
                            Text("最大").tag("largest")
                        }
                        .frame(maxWidth: 120)
                    }
                }
                .padding()

                if model.filesLoading && !model.files.items.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.bottom, 6)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.files.items.isEmpty {
                            ContentUnavailableView(
                                model.filesLoading ? "正在加载文件…" : model.fileQuery.isEmpty ? "暂无文件" : "没有匹配的文件",
                                systemImage: "folder",
                                description: Text("上传的图片和附件会集中展示在这里。")
                            )
                        }
                        ForEach(model.files.items) { item in
                            FileCenterRow(
                                item: item,
                                query: model.fileQuery,
                                model: model,
                                saving: savingID == item.id,
                                openConversation: {
                                    Task {
                                        if await model.openConversation(item.asMessageShell) {
                                            dismiss()
                                        }
                                    }
                                },
                                download: { saveFile(item) },
                                delete: { deleting = item }
                            )
                        }
                    }
                    .padding()
                }

                PageControls(page: model.filePage, totalPages: model.files.totalPages) { page in
                    model.filePage = page
                    Task { await model.loadFiles() }
                }
            }
            .navigationTitle("文件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await model.loadFiles() }
                    }
                    .disabled(model.filesLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(idealWidth: 680, idealHeight: 650)
        .onAppear { model.filesOpen = true }
        .onDisappear { model.filesOpen = false }
        .task { await model.loadFiles() }
        .task(id: model.fileQuery) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            model.filePage = 1
            await model.loadFiles()
        }
        .onChange(of: model.fileCategory) { _, _ in
            model.filePage = 1
            Task { await model.loadFiles() }
        }
        .onChange(of: model.fileSort) { _, _ in
            model.filePage = 1
            Task { await model.loadFiles() }
        }
        .fileExporter(
            isPresented: $exporting,
            document: document,
            contentType: .data,
            defaultFilename: exportingFilename
        ) { result in
            if case .failure(let error) = result {
                model.error = userFacingError(error)
            }
            document = nil
        }
        .alert(
            "删除这个文件？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let item = deleting {
                    Task {
                        do { try await model.deleteFile(item) }
                        catch { model.error = userFacingError(error) }
                    }
                }
                deleting = nil
            }
        } message: {
            Text("“\(deleting?.name ?? "")”将从所有设备永久删除，消息文字会保留。")
        }
    }

    private func saveFile(_ item: FileItem) {
        guard savingID == nil else { return }
        savingID = item.id
        Task {
            defer { savingID = nil }
            do {
                let data: Data
                if item.kind == "image" {
                    guard let loaded = await model.imageData(item.messageId) else {
                        throw APIError(message: "读取图片失败")
                    }
                    data = loaded
                } else {
                    data = try await model.attachmentData(item.asMessageShell, file: item.asAttachment)
                }
                exportingFilename = item.name
                document = AttachmentDocument(data: data)
                exporting = true
            } catch {
                model.error = userFacingError(error)
            }
        }
    }
}

private struct FileCenterRow: View {
    let item: FileItem
    let query: String
    let model: WorkspaceModel
    let saving: Bool
    let openConversation: () -> Void
    let download: () -> Void
    let delete: () -> Void
    @State private var previewData: Data?
    @State private var expanded = false

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: item.createdAt) else { return item.createdAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previewData, let image = platformImage(previewData) {
                Button { expanded = true } label: {
                    image.resizable().scaledToFit().frame(maxWidth: 480, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $expanded) {
                    VStack {
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Button("完成") { expanded = false }
                        }
                        .padding()
                        image.resizable().scaledToFit().padding()
                    }
                    .frame(idealWidth: 640, idealHeight: 520)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: item.category == "image" ? "photo" : "doc")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    HighlightedText(text: item.name, query: query)
                        .font(.callout)
                        .lineLimit(2)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) · \(item.conversationTitle) · \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("定位会话", action: openConversation)
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button(action: download) {
                    if saving { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.down.to.line") }
                }
                .buttonStyle(.borderless)
                .disabled(saving || model.isMutatingMessage(item.messageId))
                .accessibilityLabel("保存文件")
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(saving || model.isMutatingMessage(item.messageId))
                .accessibilityLabel("删除文件")
            }
        }
        .padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .task(id: "\(item.kind)-\(item.id)") {
            guard item.hasPreview else { return }
            if item.kind == "image" {
                previewData = await model.imageData(item.messageId)
            } else {
                previewData = try? await model.attachmentData(item.asMessageShell, file: item.asAttachment, preview: true)
            }
        }
    }
}
