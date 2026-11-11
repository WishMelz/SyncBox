import XCTest
@testable import SyncBoxCore

final class MessagePresentationTests: XCTestCase {
    func testLiteralMatchingPreservesOriginalUTF16Ranges() {
        let text = "😀中文 SyncBOX syncbox [a+b]"
        let source = text as NSString
        let matches = MessagePresentation.matches(text, query: " syncbox ")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map { source.substring(with: $0) }, ["SyncBOX", "syncbox"])
        XCTAssertEqual(MessagePresentation.matches(text, query: "[a+b]").count, 1)
        XCTAssertEqual(MessagePresentation.matches(text, query: "😀").first, NSRange(location: 0, length: 2))
        XCTAssertTrue(MessagePresentation.matches(text, query: " ").isEmpty)
        XCTAssertEqual(MessagePresentation.matches("中文中文", query: "中文").count, 2)
    }

    func testLinksTrimPunctuationWithoutChangingOriginal() {
        let text = "https://example.com/a_(b)， HTTPS://example.com/x?q=SyncBOX。 javascript:alert(1) ftp://example.com"
        let source = text as NSString
        let links = MessagePresentation.links(text)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links.map { source.substring(with: $0.range) }, ["https://example.com/a_(b)", "HTTPS://example.com/x?q=SyncBOX"])
        XCTAssertEqual(links[1].url.absoluteString, "HTTPS://example.com/x?q=SyncBOX")
        XCTAssertTrue(MessagePresentation.links("https://").isEmpty)
    }

    func testDayBoundariesAndISODateVariants() {
        XCTAssertNotNil(MessagePresentation.date("2026-11-09T08:00:00.123Z"))
        XCTAssertNotNil(MessagePresentation.date("2026-11-09T08:00:00Z"))
        XCTAssertFalse(MessagePresentation.startsDay("2026-11-09T08:00:00Z", previous: "2026-11-09T08:00:01.000Z"))
        XCTAssertTrue(MessagePresentation.startsDay("2026-11-09T08:00:00Z", previous: "2026-11-07T08:00:00Z"))
        XCTAssertTrue(MessagePresentation.startsDay("2026-11-09T08:00:00Z", previous: nil))
    }
}
