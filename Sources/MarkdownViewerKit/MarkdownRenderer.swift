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
    ///
    /// The template must contain `{{CONTENT}}`. If it also contains `{{EXTRA_HEAD}}`
    /// or `{{BODY_ATTRS}}`, those placeholders are replaced with empty strings.
    /// For theme or body-class injection, use the 4-argument overload.
    public func renderFull(markdown: String, templateHTML: String) -> String {
        let body = renderBody(markdown: markdown)
        return templateHTML
            .replacingOccurrences(of: "{{EXTRA_HEAD}}", with: "")
            .replacingOccurrences(of: "{{BODY_ATTRS}}", with: "")
            .replacingOccurrences(of: "{{CONTENT}}", with: body)
    }

    /// Renders full HTML with optional extra stylesheets injected into the head
    /// and optional CSS classes applied to `<body>`.
    ///
    /// Template placeholders: `{{EXTRA_HEAD}}`, `{{BODY_ATTRS}}`, `{{CONTENT}}`.
    ///
    /// - Important: Values in `extraStylesheetHrefs` and `bodyClasses` are
    ///   interpolated verbatim into HTML attributes with no escaping. Callers
    ///   must supply only trusted, well-formed values (e.g., known stylesheet
    ///   filenames). Passing values containing `"` or `<` will corrupt the
    ///   document and in hostile cases could enable injection.
    public func renderFull(
        markdown: String,
        templateHTML: String,
        extraStylesheetHrefs: [String],
        bodyClasses: [String] = []
    ) -> String {
        // Cheap structural guards — callers must not pass values that break
        // out of the HTML attribute quotes.
        for href in extraStylesheetHrefs {
            precondition(!href.contains("\""), "stylesheet href contains a quote: \(href)")
        }
        for cls in bodyClasses {
            precondition(!cls.contains("\""), "body class contains a quote: \(cls)")
        }

        let body = renderBody(markdown: markdown)

        let linkTags = extraStylesheetHrefs
            .map { "<link rel=\"stylesheet\" href=\"\($0)\">" }
            .joined(separator: "\n    ")

        let bodyAttrs: String = bodyClasses.isEmpty
            ? ""
            : " class=\"\(bodyClasses.joined(separator: " "))\""

        return templateHTML
            .replacingOccurrences(of: "{{EXTRA_HEAD}}", with: linkTags)
            .replacingOccurrences(of: "{{BODY_ATTRS}}", with: bodyAttrs)
            .replacingOccurrences(of: "{{CONTENT}}", with: body)
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
