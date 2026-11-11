import Foundation

enum MessagePresentation {
    struct Link { let range: NSRange; let url: URL }

    static func matches(_ text: String, query: String) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let source = text as NSString
        var result: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let range = source.range(of: needle, options: [.caseInsensitive, .literal], range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound else { break }
            result.append(range)
            cursor = NSMaxRange(range)
        }
        return result
    }

    static func links(_ text: String) -> [Link] {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"'　]+", options: .caseInsensitive) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            var candidate = source.substring(with: match.range)
            let punctuation = CharacterSet(charactersIn: ".,!?;:，。！？；：、）】》」』")
            candidate = candidate.trimmingCharacters(in: punctuation)
            for (open, close) in [("(", ")"), ("[", "]")] {
                while candidate.hasSuffix(close) && candidate.components(separatedBy: close).count > candidate.components(separatedBy: open).count { candidate.removeLast() }
            }
            guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
            return Link(range: NSRange(location: match.range.location, length: (candidate as NSString).length), url: url)
        }
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func startsDay(_ value: String, previous: String?) -> Bool {
        guard let previous, let current = date(value), let earlier = date(previous) else { return true }
        return !Calendar.current.isDate(current, inSameDayAs: earlier)
    }

    static func dayLabel(_ value: String) -> String {
        guard let date = date(value) else { return value }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.year().month().day())
    }
}
