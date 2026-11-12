import SwiftUI
import UniformTypeIdentifiers

struct AttachmentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct AttachmentView: View {
    let message: Message
    let file: Attachment
    let model: WorkspaceModel
    var query = ""
    @State private var preview: Data?
    @State private var document: AttachmentDocument?
    @State private var exporting = false
    @State private var downloading = false
    @State private var expanded = false
    @State private var previewFailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview, let image = platformImage(preview) {
                Button { expanded = true } label: { image.resizable().scaledToFit().frame(maxWidth: 480, maxHeight: 240) }.buttonStyle(.plain).accessibilityLabel("预览图片")
                    .sheet(isPresented: $expanded) { VStack { HStack { Text(file.name).lineLimit(1); Spacer(); Button("完成") { expanded = false } }.padding(); image.resizable().scaledToFit().padding() }.frame(idealWidth: 600, idealHeight: 500) }
            } else if previewFailed { Button("预览加载失败，重试") { Task { await loadPreview() } }.font(.caption) }
            HStack(spacing: 10) {
                Image(systemName: "doc")
                VStack(alignment: .leading, spacing: 3) {
                    HighlightedText(text: file.name, query: query).font(.callout).lineLimit(MessagePresentation.matches(file.name, query: query).isEmpty ? 2 : nil)
                    Text(file.deletedAt != nil ? "文件已清理" : ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(ChatStyle.muted)
                }
                Spacer()
                Button {
                    downloading = true
                    Task {
                        defer { downloading = false }
                        do { document = AttachmentDocument(data: try await model.attachmentData(message, file: file)); exporting = true }
                        catch { model.error = userFacingError(error) }
                    }
                } label: { Label(downloading ? "保存中…" : "保存文件", systemImage: "arrow.down.to.line") }.labelStyle(.iconOnly).disabled(file.deletedAt != nil || downloading)
            }.padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .task(id: file.id) { if file.hasPreview == true && file.deletedAt == nil { await loadPreview() } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: file.name) { result in
            if case .failure(let error) = result { model.error = userFacingError(error) }
            document = nil
        }
    }
    private func loadPreview() async {
        do { preview = try await model.attachmentData(message, file: file, preview: true); previewFailed = false }
        catch { previewFailed = true }
    }
}
