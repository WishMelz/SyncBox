import Foundation

/// Keeps UTF-8 code points and SSE frames intact across network chunks.
struct SyncEventParser {
    private var line: [UInt8] = []
    private var data: [String] = []
    private var event = ""
    private var size = 0

    mutating func add(_ byte: UInt8) throws -> SyncEvent? {
        size += 1
        guard size <= 65536 else { throw APIError(message: "实时同步事件过大") }
        guard byte == 10 else { line.append(byte); return nil }
        if line.last == 13 { line.removeLast() }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { data.removeAll(); event = ""; size = 0 }
            guard !data.isEmpty, event.isEmpty || event == "sync" else { return nil }
            let decoded = try JSONDecoder().decode(SyncEvent.self, from: Data(data.joined(separator: "\n").utf8))
            return decoded.type == "invalidate" ? decoded : nil
        }
        if text.hasPrefix(":") { return nil }
        let fields = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = fields.count == 2 ? String(fields[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if fields[0] == "data" { data.append(value) }
        if fields[0] == "event" { event = value }
        return nil
    }
}
