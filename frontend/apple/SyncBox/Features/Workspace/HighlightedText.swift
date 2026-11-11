import SwiftUI

enum ChatStyle {
    static let blue = Color(red: 0.086, green: 0.47, blue: 0.68)
    static let background = Color(red: 0.906, green: 0.933, blue: 0.953)
    static let outgoing = Color(red: 0.863, green: 0.933, blue: 0.976)
    static let ink = Color(red: 0.14, green: 0.2, blue: 0.25)
    static let muted = Color(red: 0.38, green: 0.47, blue: 0.52)
}

struct HighlightedText: View {
    let text: String
    var query = ""
    var links = false

    private var attributed: AttributedString {
        var result = AttributedString(text)
        if links {
            for link in MessagePresentation.links(text) {
                if let range = Range(link.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: result), let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].link = link.url
                    result[lower..<upper].foregroundColor = ChatStyle.blue
                    result[lower..<upper].underlineStyle = .single
                }
            }
        }
        for match in MessagePresentation.matches(text, query: query) {
            if let range = Range(match, in: text), let lower = AttributedString.Index(range.lowerBound, within: result), let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].backgroundColor = Color(red: 1, green: 0.89, blue: 0.60)
                result[lower..<upper].foregroundColor = Color(red: 0.32, green: 0.23, blue: 0.03)
            }
        }
        return result
    }

    var body: some View { Text(attributed) }
}
