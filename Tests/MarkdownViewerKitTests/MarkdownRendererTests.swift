import XCTest
@testable import MarkdownViewerKit

final class MarkdownRendererTests: XCTestCase {

    func testPlainMarkdownToHTML() {
        let markdown = "# Hello\n\nThis is **bold** text.\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
    }

    func testMermaidBlockBecomesDiv() {
        let markdown = "# Test\n\n```mermaid\ngraph TD\n    A --> B\n```\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("<div class=\"mermaid\""))
        XCTAssertTrue(html.contains("graph TD"))
        XCTAssertFalse(html.contains("```mermaid"))
    }

    func testPlantUMLBlockShowsPlaceholderWhenNotInstalled() {
        let markdown = "```plantuml\n@startuml\nA -> B\n@enduml\n```\n"
        let renderer = MarkdownRenderer(plantUMLBinaryPath: "/nonexistent/plantuml")
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("plantuml-placeholder") || html.contains("<svg"),
                      "Expected either placeholder or SVG")
    }

    func testRegularCodeBlocksPreserved() {
        let markdown = "```swift\nlet x = 42\n```\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("let x = 42"))
        XCTAssertFalse(html.contains("mermaid"))
    }

    func testFullHTMLIncludesTemplate() {
        let markdown = "# Hello\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderFull(markdown: markdown, templateHTML: "<html><body>{{CONTENT}}</body></html>")
        XCTAssertTrue(html.contains("<html>"))
        XCTAssertTrue(html.contains("<h1>"))
    }

    func testRenderFullAppliesTheme() {
        let template = """
        <html><head>{{EXTRA_HEAD}}</head><body{{BODY_ATTRS}}>{{CONTENT}}</body></html>
        """
        let renderer = MarkdownRenderer()
        let html = renderer.renderFull(
            markdown: "# Hi",
            templateHTML: template,
            extraStylesheetHrefs: ["themes/technical.css", "pdf-overlay.css"],
            bodyClasses: ["pdf-start-h1-new-page"]
        )
        XCTAssertTrue(html.contains("themes/technical.css"))
        XCTAssertTrue(html.contains("pdf-overlay.css"))
        XCTAssertTrue(html.contains("<body class=\"pdf-start-h1-new-page\">"))
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
    }
}
