import XCTest
@testable import MarkdownViewerKit

final class HeadingExtractorTests: XCTestCase {

    func testNoHeadings() {
        let markdown = "Some plain text.\n\nMore text.\n"
        let headings = HeadingExtractor.extract(from: markdown)
        XCTAssertTrue(headings.isEmpty)
    }

    func testSingleH1() {
        let markdown = "# Hello World\n\nSome text.\n"
        let headings = HeadingExtractor.extract(from: markdown)
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].level, 1)
        XCTAssertEqual(headings[0].text, "Hello World")
    }

    func testMultipleLevels() {
        let markdown = """
        # Title
        ## Section One
        ### Subsection
        ## Section Two
        """
        let headings = HeadingExtractor.extract(from: markdown)
        XCTAssertEqual(headings.count, 4)
        XCTAssertEqual(headings[0].level, 1)
        XCTAssertEqual(headings[0].text, "Title")
        XCTAssertEqual(headings[1].level, 2)
        XCTAssertEqual(headings[1].text, "Section One")
        XCTAssertEqual(headings[2].level, 3)
        XCTAssertEqual(headings[2].text, "Subsection")
        XCTAssertEqual(headings[3].level, 2)
        XCTAssertEqual(headings[3].text, "Section Two")
    }

    func testIgnoresCodeBlocks() {
        let markdown = """
        # Real Heading

        ```
        # Not a heading
        ## Also not
        ```

        ## Another Real Heading
        """
        let headings = HeadingExtractor.extract(from: markdown)
        XCTAssertEqual(headings.count, 2)
        XCTAssertEqual(headings[0].text, "Real Heading")
        XCTAssertEqual(headings[1].text, "Another Real Heading")
    }

    func testHeadingWithInlineFormatting() {
        let markdown = "# Hello **bold** and *italic*\n"
        let headings = HeadingExtractor.extract(from: markdown)
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "Hello **bold** and *italic*")
    }
}
