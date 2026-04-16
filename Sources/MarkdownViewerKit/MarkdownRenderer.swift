import Foundation
import cmark_gfm
import cmark_gfm_extensions

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
        let options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE

        cmark_gfm_core_extensions_ensure_registered()

        guard let parser = cmark_parser_new(options) else {
            return "<p>Failed to render markdown.</p>"
        }
        defer { cmark_parser_free(parser) }

        for ext in ["table", "strikethrough", "autolink", "tasklist"] {
            if let syntax = cmark_find_syntax_extension(ext) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)

        guard let doc = cmark_parser_finish(parser) else {
            return "<p>Failed to render markdown.</p>"
        }
        defer { cmark_node_free(doc) }

        guard let cString = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else {
            return "<p>Failed to render markdown.</p>"
        }
        defer { free(cString) }
        return String(cString: cString)
    }
}
