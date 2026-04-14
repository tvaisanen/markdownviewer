import XCTest
@testable import MarkdownViewerKit

final class MermaidRendererTests: XCTestCase {

    func testRenderWrapsInDiv() {
        let source = "graph TD\n    A --> B"
        let html = MermaidRenderer.render(source: source)
        XCTAssertTrue(html.contains("<div class=\"mermaid\""))
        XCTAssertTrue(html.contains("graph TD"))
        XCTAssertTrue(html.contains("A --> B"))
        XCTAssertTrue(html.contains("</div>"))
    }

    func testRenderIncludesDataSource() {
        let source = "graph LR\n    X --> Y"
        let html = MermaidRenderer.render(source: source)
        XCTAssertTrue(html.contains("data-source="))
    }

    func testRenderEscapesHTMLInDataSource() {
        let source = "graph TD\n    A[\"<script>alert('xss')</script>\"] --> B"
        let html = MermaidRenderer.render(source: source)
        // data-source attribute must have HTML-escaped content
        XCTAssertFalse(html.contains("<script>alert"))
    }
}
