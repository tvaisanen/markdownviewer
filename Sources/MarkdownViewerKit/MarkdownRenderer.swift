import Foundation
import cmark_gfm

public final class MarkdownRenderer: Sendable {

    private let plantUMLRenderer: PlantUMLRenderer

    public init(plantUMLBinaryPath: String? = nil) {
        self.plantUMLRenderer = PlantUMLRenderer(binaryPath: plantUMLBinaryPath)
    }

    /// Renders markdown to an HTML body fragment (no <html>/<head> wrapper).
    public func renderBody(markdown: String) -> String {
        // 1. Extract diagram blocks, replace with placeholders
        let extraction = DiagramProcessor.extractDiagrams(from: markdown)

        // 2. Render each diagram block
        var renderedBlocks: [String: String] = [:]
        for block in extraction.blocks {
            switch block.type {
            case .mermaid:
                renderedBlocks[block.id] = MermaidRenderer.render(source: block.source)
            case .plantuml:
                renderedBlocks[block.id] = plantUMLRenderer.render(source: block.source)
            }
        }

        // 3. Convert remaining markdown to HTML via cmark
        let cmarkHTML = cmarkToHTML(extraction.processedMarkdown)

        // 4. Inject rendered diagrams back into HTML
        return DiagramProcessor.injectDiagrams(into: cmarkHTML, renderedBlocks: renderedBlocks)
    }

    /// Renders markdown into a full HTML document using the given template.
    /// The template must contain `{{CONTENT}}` as the placeholder.
    public func renderFull(markdown: String, templateHTML: String) -> String {
        let body = renderBody(markdown: markdown)
        return templateHTML.replacingOccurrences(of: "{{CONTENT}}", with: body)
    }

    private func cmarkToHTML(_ markdown: String) -> String {
        guard let cString = cmark_markdown_to_html(
            markdown,
            markdown.utf8.count,
            CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE
        ) else {
            return "<p>Failed to render markdown.</p>"
        }
        defer { free(cString) }
        return String(cString: cString)
    }
}
