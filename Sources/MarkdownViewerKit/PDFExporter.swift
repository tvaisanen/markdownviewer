import Foundation
import WebKit
import PDFKit

public enum PDFExportError: Error {
    case templateUnavailable
    case createPDFFailed(Error)
    case emptyContent
}

@MainActor
public final class PDFExporter {

    private let renderer: MarkdownRenderer
    private let bundle: Bundle

    public init(renderer: MarkdownRenderer = MarkdownRenderer(), bundle: Bundle = .main) {
        self.renderer = renderer
        self.bundle = bundle
    }

    /// Generate a PDF from the given markdown under the supplied options.
    /// `documentTitle` is used for the running header when enabled.
    public func exportPDF(
        markdown: String,
        options: PDFExportOptions,
        documentTitle: String
    ) async throws -> Data {
        let templateHTML = try loadTemplate()
        let extraStylesheets = [
            "themes/\(options.theme.stylesheetFilename)",
            "pdf-overlay.css"
        ]
        var bodyClasses: [String] = []
        if options.startNewPageAtH1 { bodyClasses.append("pdf-start-h1-new-page") }

        let injectedPageCSS = makePageCSS(options: options, title: documentTitle)
        let html = renderer.renderFull(
            markdown: markdown,
            templateHTML: injectPageCSS(into: templateHTML, css: injectedPageCSS),
            extraStylesheetHrefs: extraStylesheets,
            bodyClasses: bodyClasses
        )

        let pageSize = options.paperSize.pointSize(orientation: options.orientation)
        let webView = makeOffscreenWebView(pageSize: pageSize)

        let baseURL = bundle.resourceURL
        try await loadHTML(html: html, baseURL: baseURL, in: webView)

        _ = await DiagramRenderCoordinator.waitForDiagrams(in: webView)

        if options.startNewPageAtH1 {
            await applyH1PageBreaks(in: webView, pageHeight: pageSize.height)
        }
        await applyBreakInsideAvoidPadding(in: webView, pageHeight: pageSize.height)

        return try await createPDF(from: webView, pageSize: pageSize)
    }

    // MARK: - Private

    private func loadTemplate() throws -> String {
        guard
            let url = bundle.url(forResource: "template", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw PDFExportError.templateUnavailable
        }
        return html
    }

    /// Insert a page-media `<style>` block right after `{{EXTRA_HEAD}}`.
    private func injectPageCSS(into template: String, css: String) -> String {
        let styleTag = "<style>\n\(css)\n</style>"
        return template.replacingOccurrences(
            of: "{{EXTRA_HEAD}}",
            with: "{{EXTRA_HEAD}}\n    \(styleTag)"
        )
    }

    private func makePageCSS(options: PDFExportOptions, title: String) -> String {
        let size = options.paperSize.pointSize(orientation: options.orientation)
        let widthIn = size.width / 72.0
        let heightIn = size.height / 72.0

        let headerRule: String = options.showHeader
            ? "@top-right { content: \"\(escapeCSS(options.headerText ?? title))\"; font-size: 9pt; color: #888; }"
            : ""
        let footerRule: String = options.showFooter
            ? "@bottom-center { content: counter(page); font-size: 9pt; color: #888; }"
            : ""

        return """
        @page {
            size: \(widthIn)in \(heightIn)in;
            margin: 0.75in;
            \(headerRule)
            \(footerRule)
        }
        """
    }

    private func escapeCSS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Uses `padding-top` so the heading's own background/underline (if any)
    /// extends into the injected space.
    /// For each H1 (except the very first), add a `padding-top` so that it falls exactly
    /// at the start of the next page slice. This ensures the pixel-slicing `createPDF`
    /// produces a fresh page for each top-level heading.
    private func applyH1PageBreaks(in webView: WKWebView, pageHeight: CGFloat) async {
        let js = """
        (function() {
            var pageH = \(pageHeight);
            var h1s = Array.from(document.querySelectorAll('h1'));
            var seen = false;
            h1s.forEach(function(h1) {
                if (!seen) { seen = true; return; } // skip first H1
                var rect = h1.getBoundingClientRect();
                var scrollY = window.scrollY;
                var absTop = rect.top + scrollY;
                var currentPage = Math.floor(absTop / pageH);
                var pageTop = currentPage * pageH;
                var offset = absTop - pageTop;
                if (offset > 0) {
                    var extra = pageH - offset;
                    var current = parseFloat(window.getComputedStyle(h1).paddingTop) || 0;
                    h1.style.paddingTop = (current + extra) + 'px';
                }
            });
        })();
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { _, _ in c.resume() }
        }
    }

    /// Uses `margin-top` rather than `padding-top` so the injected space does
    /// not accumulate with the H1 padding from `applyH1PageBreaks`, and so
    /// element backgrounds (e.g., image frames, table borders) stay tight
    /// against the element instead of extending through the gap.
    /// Emulate `break-inside: avoid` for images, figures, diagrams, tables, and rows
    /// by injecting `margin-top` so elements that would straddle a pixel-slice boundary
    /// start on the next page instead. Elements taller than a page are left alone
    /// (no amount of padding fixes them; they will span multiple pages).
    private func applyBreakInsideAvoidPadding(in webView: WKWebView, pageHeight: CGFloat) async {
        let js = """
        (function() {
            var pageH = \(pageHeight);
            var selectors = 'img, svg, figure, .mermaid, .plantuml-placeholder, .plantuml-error, table, tr';
            // Ancestor selectors: if an element's ancestor already appears in our list,
            // pad the ancestor instead (avoids double-padding nested elements like
            // an <svg> inside a <.mermaid> div, or a <tr> already handled via <table>).
            var ancestorSelectors = 'figure, .mermaid, .plantuml-placeholder, .plantuml-error, table';

            function hasMatchingAncestor(el) {
                var parent = el.parentElement;
                while (parent) {
                    if (parent.matches(ancestorSelectors)) return true;
                    parent = parent.parentElement;
                }
                return false;
            }

            function padStraddlers() {
                var els = Array.from(document.querySelectorAll(selectors));
                // Snapshot rects before any writes to avoid reflow mid-loop.
                var items = els.map(function(el) {
                    return { el: el, rect: el.getBoundingClientRect() };
                });
                var paddedAny = false;
                items.forEach(function(item) {
                    var el = item.el;
                    if (el.getAttribute('data-pdf-padded') === '1') return;
                    // Skip elements whose ancestor is already in our selector list —
                    // padding the ancestor will move the child automatically.
                    if (hasMatchingAncestor(el)) return;
                    var rect = item.rect;
                    var h = rect.height;
                    if (h <= 0 || h >= pageH) return; // zero / oversized — skip
                    var absTop = rect.top + window.scrollY;
                    var topPage = Math.floor(absTop / pageH);
                    var bottomPage = Math.floor((absTop + h - 1) / pageH);
                    if (topPage === bottomPage) return; // fits on one page already
                    var pageTop = topPage * pageH;
                    var offsetInPage = absTop - pageTop;
                    var push = pageH - offsetInPage;
                    var current = parseFloat(window.getComputedStyle(el).marginTop) || 0;
                    el.style.marginTop = (current + push) + 'px';
                    el.setAttribute('data-pdf-padded', '1');
                    paddedAny = true;
                });
                return paddedAny;
            }

            // Bounded cascade: each padding round shifts later elements; keep
            // iterating until no new straddlers remain or we hit the cap.
            var iterations = 0;
            while (padStraddlers() && iterations < 10) { iterations++; }
        })();
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { _, _ in c.resume() }
        }
    }

    private func makeOffscreenWebView(pageSize: CGSize) -> WKWebView {
        let config = WKWebViewConfiguration()
        return WKWebView(
            frame: CGRect(origin: .zero, size: pageSize),
            configuration: config
        )
    }

    private func loadHTML(html: String, baseURL: URL?, in webView: WKWebView) async throws {
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        _ = delegate              // retain until navigation completes
        webView.navigationDelegate = nil
    }

    private func createPDF(from webView: WKWebView, pageSize: CGSize) async throws -> Data {
        // Measure content height via JavaScript, then slice the content into page-sized
        // rects and stitch them into a single PDFDocument.
        // Note: this approach uses pixel-slicing and does NOT honour CSS break-before/break-after.
        // CSS print-media page breaks (e.g. body.pdf-start-h1-new-page h1) cannot be applied
        // with this method — they require NSPrintOperation attached to a visible window.
        let rawHeight = await withCheckedContinuation { (c: CheckedContinuation<CGFloat, Never>) in
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                if let num = result as? NSNumber {
                    c.resume(returning: CGFloat(truncating: num))
                } else {
                    c.resume(returning: pageSize.height)
                }
            }
        }
        guard rawHeight > 0 else {
            throw PDFExportError.emptyContent
        }
        let totalHeight = max(rawHeight, pageSize.height)
        let pageCount = Int(ceil(totalHeight / pageSize.height))

        let combined = PDFDocument()
        for pageIndex in 0..<pageCount {
            let y = CGFloat(pageIndex) * pageSize.height
            let rect = CGRect(x: 0, y: y, width: pageSize.width, height: pageSize.height)
            let config = WKPDFConfiguration()
            config.rect = rect
            let data: Data = try await withCheckedThrowingContinuation { c in
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let d): c.resume(returning: d)
                    case .failure(let e): c.resume(throwing: PDFExportError.createPDFFailed(e))
                    }
                }
            }
            if let page = PDFDocument(data: data)?.page(at: 0) {
                combined.insert(page, at: combined.pageCount)
            }
        }

        return combined.dataRepresentation() ?? Data()
    }
}

@MainActor
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinish?()
    }
}
