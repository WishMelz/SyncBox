import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

func platformImage(_ data: Data) -> Image? {
    #if os(macOS)
    NSImage(data: data).map { Image(nsImage: $0) }
    #else
    UIImage(data: data).map { Image(uiImage: $0) }
    #endif
}

func prepareImage(_ data: Data) throws -> Data {
    guard data.count <= 8 * 1024 * 1024,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 24_000_000 / height else {
        throw APIError(message: "请选择不超过 8 MB、2400 万像素的图片")
    }
    let type = CGImageSourceGetType(source) as String?
    if [UTType.jpeg.identifier, UTType.png.identifier, UTType.webP.identifier, UTType.gif.identifier].contains(type ?? "") { return data }
    // Convert HEIC and other system-supported photo formats for the backend.
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw APIError(message: "无法读取图片") }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw APIError(message: "无法转换图片") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9, kCGImagePropertyOrientation: properties[kCGImagePropertyOrientation] ?? 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination), output.length <= 8 * 1024 * 1024 else { throw APIError(message: "图片转换后超过 8 MB") }
    return output as Data
}

struct ImageMessageView: View {
    let messageID: String
    let model: WorkspaceModel
    @State private var data: Data?
    @State private var loading = true
    @State private var expanded = false
    var body: some View {
        Group {
            if let data, let image = platformImage(data) {
                Button { expanded = true } label: {
                    image.resizable().scaledToFit().frame(maxWidth: 480, maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel("查看图片")
                .sheet(isPresented: $expanded) {
                    VStack {
                        HStack { Text("图片预览").font(.headline); Spacer(); Button("完成") { expanded = false } }.padding()
                        image.resizable().scaledToFit().padding()
                    }.frame(idealWidth: 700, idealHeight: 600)
                }
            } else if loading { ProgressView("加载图片…").padding() }
            else { Button("图片加载失败，重试") { Task { await load() } } }
        }.task(id: messageID) { await load() }
    }
    private func load() async {
        loading = true
        data = await model.imageData(messageID)
        loading = false
    }
}
