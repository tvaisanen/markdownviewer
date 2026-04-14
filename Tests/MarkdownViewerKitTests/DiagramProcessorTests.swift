import XCTest
@testable import MarkdownViewerKit

final class DiagramProcessorTests: XCTestCase {

    func testNoDiagrams() {
        let markdown = "# Hello\n\nSome text.\n"
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.processedMarkdown, markdown)
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func testExtractMermaidBlock() {
        let markdown = """
        # Title

        ```mermaid
        graph TD
            A --> B
        ```

        After.
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].type, .mermaid)
        XCTAssertTrue(result.blocks[0].source.contains("graph TD"))
        XCTAssertTrue(result.processedMarkdown.contains("<!--DIAGRAM:"))
        XCTAssertFalse(result.processedMarkdown.contains("```mermaid"))
    }

    func testExtractPlantUMLBlock() {
        let markdown = """
        # Title

        ```plantuml
        @startuml
        Alice -> Bob: Hello
        @enduml
        ```

        After.
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].type, .plantuml)
        XCTAssertTrue(result.blocks[0].source.contains("Alice -> Bob"))
    }

    func testExtractMixedBlocks() {
        let markdown = """
        ```mermaid
        graph LR
            A --> B
        ```

        ```plantuml
        @startuml
        A -> B
        @enduml
        ```

        ```swift
        let x = 1
        ```
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.blocks[0].type, .mermaid)
        XCTAssertEqual(result.blocks[1].type, .plantuml)
        // Regular code blocks are untouched
        XCTAssertTrue(result.processedMarkdown.contains("```swift"))
    }

    func testInjectRenderedDiagrams() {
        let markdown = "```mermaid\ngraph TD\n    A --> B\n```\n"
        let extracted = DiagramProcessor.extractDiagrams(from: markdown)
        let rendered = [extracted.blocks[0].id: "<div class=\"mermaid\">graph TD\n    A --> B</div>"]
        let html = DiagramProcessor.injectDiagrams(into: extracted.processedMarkdown, renderedBlocks: rendered)
        XCTAssertTrue(html.contains("<div class=\"mermaid\">"))
        XCTAssertFalse(html.contains("<!--DIAGRAM:"))
    }
}
