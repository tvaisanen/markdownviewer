import Foundation
import WebKit
import PDFKit

public enum PDFExportError: Error {
    case templateUnavailable
    case createPDFFailed(Error)
    case emptyContent
}

public struct PDFExportResult: Sendable {
    public let data: Data
    /// Page indexes (0-based) where at least one image or diagram was rendered
    /// at less than 70% of its natural linear size (≈49% area).
    public let scaledPageIndexes: [Int]
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
    ) async throws -> PDFExportResult {
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
        // Reserve vertical whitespace at the top and bottom of each printed page.
        // We slice the webview content at `sliceHeight` and later expand each
        // slice's mediaBox to full `pageSize`, centering the content vertically.
        let verticalMargin: CGFloat = 54 // 0.75 in
        let sliceHeight = max(pageSize.height - 2 * verticalMargin, pageSize.height * 0.5)
        let sliceSize = CGSize(width: pageSize.width, height: sliceHeight)
        let webView = makeOffscreenWebView(pageSize: sliceSize)

        let baseURL = bundle.resourceURL
        try await loadHTML(html: html, baseURL: baseURL, in: webView)

        _ = await DiagramRenderCoordinator.waitForDiagrams(in: webView)

        if options.startNewPageAtH1 {
            await applyH1PageBreaks(in: webView, pageHeight: sliceHeight)
        }
        await applyOversizedSectionScaling(in: webView, pageHeight: sliceHeight)
        await applyPaginationRules(in: webView, pageHeight: sliceHeight)
        await applyTitlePageCentering(in: webView, pageHeight: sliceHeight)

        let scaledPages = await detectScaledImages(in: webView, pageHeight: sliceHeight)
        let rawData = try await createPDF(
            from: webView,
            pageSize: pageSize,
            sliceHeight: sliceHeight,
            verticalMargin: verticalMargin
        )
        let data = stampPageChrome(
            pdfData: rawData,
            pageSize: pageSize,
            verticalMargin: verticalMargin,
            options: options,
            documentTitle: documentTitle
        )
        return PDFExportResult(data: data, scaledPageIndexes: scaledPages)
    }

    // MARK: - Private

    /// Returns page indexes (0-based) where images/diagrams were scaled to fit.
    /// Uses a 49% area threshold (≈70% on each linear axis).
    private func detectScaledImages(in webView: WKWebView, pageHeight: CGFloat) async -> [Int] {
        let js = """
        (function() {
            var pages = new Set();
            var els = document.querySelectorAll('img, svg, .mermaid');
            els.forEach(function(el) {
                var rect = el.getBoundingClientRect();
                var natural = 0;
                if (el.tagName === 'IMG') {
                    natural = (el.naturalWidth || 0) * (el.naturalHeight || 0);
                } else if (el.tagName === 'SVG') {
                    var w = parseFloat(el.getAttribute('width')) || rect.width;
                    var h = parseFloat(el.getAttribute('height')) || rect.height;
                    natural = w * h;
                } else {
                    // .mermaid: use the inner SVG's intrinsic size if present
                    var svg = el.querySelector('svg');
                    if (svg) {
                        var w = parseFloat(svg.getAttribute('width')) || svg.getBoundingClientRect().width;
                        var h = parseFloat(svg.getAttribute('height')) || svg.getBoundingClientRect().height;
                        natural = w * h;
                    }
                }
                var rendered = rect.width * rect.height;
                if (natural > 0 && rendered > 0 && (rendered / natural) < 0.49) {
                    var pageIndex = Math.floor((rect.top + window.scrollY) / \(pageHeight));
                    pages.add(pageIndex);
                }
            });
            return Array.from(pages).sort(function(a, b) { return a - b; });
        })();
        """
        return await withCheckedContinuation { (c: CheckedContinuation<[Int], Never>) in
            webView.evaluateJavaScript(js) { result, _ in
                c.resume(returning: (result as? [Int]) ?? [])
            }
        }
    }

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

    /// Scale down figures in sections that would overflow a single page so
    /// the whole section (heading + its content) fits on one page. Uses the
    /// `zoom` CSS property, which (unlike `transform: scale`) shrinks both
    /// visual rendering and the layout footprint. A lower bound of 0.5
    /// avoids unreadable output; anything smaller than that is left to
    /// straddle or split.
    private func applyOversizedSectionScaling(in webView: WKWebView, pageHeight: CGFloat) async {
        let js = """
        (function() {
            var pageH = \(pageHeight);
            var headingSelector = 'h1, h2, h3';
            var keepWholeSelector = 'img, svg, figure, .mermaid, .plantuml-placeholder, .plantuml-error, table';
            var minScale = 0.5;
            // Section fits if <= 96% of page height (leave some breathing room).
            var fitTargetRatio = 0.96;

            // Build sections (heading + siblings up to next heading).
            var sections = [];
            var children = Array.from(document.body.children);
            var current = null;
            children.forEach(function(child) {
                if (child.matches(headingSelector)) {
                    if (current) sections.push(current);
                    current = { heading: child, members: [] };
                } else if (current) {
                    current.members.push(child);
                }
            });
            if (current) sections.push(current);

            sections.forEach(function(section) {
                if (section.members.length === 0) return;

                // Find the figures owned by this section (top-level matches only,
                // skip nested — e.g. the inner <svg> of a <.mermaid>).
                var figures = [];
                section.members.forEach(function(m) {
                    var candidates = m.matches(keepWholeSelector)
                        ? [m]
                        : Array.from(m.querySelectorAll(keepWholeSelector));
                    candidates.forEach(function(c) {
                        if (c.closest(keepWholeSelector) === c && figures.indexOf(c) === -1) {
                            figures.push(c);
                        }
                    });
                });
                if (figures.length === 0) return;

                // Measure the section's visual extent.
                var firstTop = section.heading.getBoundingClientRect().top;
                var lastBottom = section.members[section.members.length - 1]
                    .getBoundingClientRect().bottom;
                var sectionHeight = lastBottom - firstTop;
                if (sectionHeight <= pageH * fitTargetRatio) return;

                var scale = (pageH * fitTargetRatio) / sectionHeight;
                if (scale >= 1) return;
                if (scale < minScale) scale = minScale;

                // Zoom every figure in the section proportionally. If there
                // are multiple figures, each shrinks; combined section height
                // drops close to page height.
                figures.forEach(function(fig) {
                    var existingZoom = parseFloat(fig.style.zoom) || 1;
                    fig.style.zoom = (existingZoom * scale).toString();
                });
            });
        })();
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { _, _ in c.resume() }
        }
    }

    /// If the first `<h1>` is alone on page 1 (all subsequent content got
    /// pushed to page 2+ by pagination), center it vertically using a CSS
    /// `transform: translateY`. Transforms don't affect layout flow, so
    /// subsequent pages stay put.
    private func applyTitlePageCentering(in webView: WKWebView, pageHeight: CGFloat) async {
        let js = """
        (function() {
            var pageH = \(pageHeight);
            var first = document.body.firstElementChild;
            if (!first || first.tagName !== 'H1') return;
            var firstRect = first.getBoundingClientRect();
            var firstTop = firstRect.top + window.scrollY;
            var firstBottom = firstTop + firstRect.height;
            var firstPage = Math.floor(firstTop / pageH);
            // Must be on page 0 (top page of document)
            if (firstPage !== 0) return;
            var next = first.nextElementSibling;
            if (!next) return;
            var nextTop = next.getBoundingClientRect().top + window.scrollY;
            if (Math.floor(nextTop / pageH) <= firstPage) return; // not alone
            // Center the H1 vertically in the slice (page 0 runs y=0 to y=pageH).
            var h1Height = firstRect.height;
            var targetTop = (pageH - h1Height) / 2;
            var shift = targetTop - firstTop;
            if (shift <= 0) return;
            first.style.transform = 'translateY(' + shift + 'px)';
            // Add a thin rule below the title, also translated, for a subtle
            // "title page" feel. Only insert if one isn't already there.
            if (!document.querySelector('.pdf-title-rule')) {
                var rule = document.createElement('div');
                rule.className = 'pdf-title-rule';
                rule.style.width = '120px';
                rule.style.height = '2px';
                rule.style.background = '#888';
                rule.style.margin = '16px 0 0 0';
                rule.style.transform = 'translateY(' + shift + 'px)';
                first.parentNode.insertBefore(rule, first.nextSibling);
            }
        })();
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { _, _ in c.resume() }
        }
    }

    /// Group-aware pagination: emulate `break-after: avoid` (keep heading with
    /// its following content) and `break-inside: avoid` (don't split figures,
    /// diagrams, or tables) in a single pass that pushes whole sections
    /// rather than isolated elements.
    ///
    /// A "section" is a heading (h1/h2/h3) plus every sibling that follows
    /// until the next heading. If any figure/diagram/table inside the section
    /// would straddle a page boundary, OR if the heading lands near the
    /// bottom of its page, we push the *heading* so the whole section moves
    /// to the next page. This keeps heading + content travelling together.
    private func applyPaginationRules(in webView: WKWebView, pageHeight: CGFloat) async {
        let js = """
        (function() {
            var pageH = \(pageHeight);
            // "Keep-whole" block types: figures, diagrams, tables — splitting
            // these looks bad, so their section gets pushed if they'd straddle.
            var keepWholeSelector = 'img, svg, figure, .mermaid, .plantuml-placeholder, .plantuml-error, table';
            // Minimum content height a heading needs on its page before it's
            // allowed to stay — ~4 body lines or 18% of the page, whichever is less.
            var headingOrphanThreshold = Math.min(140, pageH * 0.18);
            var headingSelector = 'h1, h2, h3';

            function topY(el) {
                return el.getBoundingClientRect().top + window.scrollY;
            }

            function pageOf(y) { return Math.floor(y / pageH); }

            // Build sections: each heading starts one; its members are every
            // following sibling up to the next heading (or end of body).
            function buildSections() {
                var sections = [];
                var children = Array.from(document.body.children);
                var current = null;
                children.forEach(function(child) {
                    if (child.matches(headingSelector)) {
                        if (current) sections.push(current);
                        current = { heading: child, members: [] };
                    } else if (current) {
                        current.members.push(child);
                    }
                });
                if (current) sections.push(current);
                return sections;
            }

            // Add `margin-top` to element `el` so its top moves to the next
            // page boundary. Idempotent via a data attribute.
            function pushToNextPage(el) {
                if (el.getAttribute('data-pdf-push-applied') === '1') return false;
                var top = topY(el);
                var page = pageOf(top);
                var offset = top - page * pageH;
                if (offset <= 1) return false; // already near top
                var push = pageH - offset;
                var current = parseFloat(window.getComputedStyle(el).marginTop) || 0;
                el.style.marginTop = (current + push) + 'px';
                el.setAttribute('data-pdf-push-applied', '1');
                return true;
            }

            // Return true if any member of a section is a "keep-whole" element
            // that currently straddles a page boundary (and is small enough
            // to fit on a single page — otherwise no amount of padding helps).
            function sectionHasStraddlingFigure(section) {
                for (var i = 0; i < section.members.length; i++) {
                    var m = section.members[i];
                    var figures = m.matches(keepWholeSelector)
                        ? [m]
                        : Array.from(m.querySelectorAll(keepWholeSelector));
                    for (var j = 0; j < figures.length; j++) {
                        var fig = figures[j];
                        var rect = fig.getBoundingClientRect();
                        var h = rect.height;
                        if (h <= 0 || h >= pageH) continue;
                        var absTop = rect.top + window.scrollY;
                        var absBottom = absTop + h;
                        if (pageOf(absTop) !== pageOf(absBottom - 1)) return true;
                    }
                }
                return false;
            }

            // Return true if the heading is too close to the bottom of its
            // page to have meaningful content follow.
            function headingIsOrphaned(heading) {
                var rect = heading.getBoundingClientRect();
                var absTop = rect.top + window.scrollY;
                var absBottom = absTop + rect.height;
                var pageBottom = (pageOf(absTop) + 1) * pageH;
                var spaceAfter = pageBottom - absBottom;
                return spaceAfter >= 0 && spaceAfter < headingOrphanThreshold;
            }

            // One pass: walk sections in document order; if a section violates
            // either rule, push the heading to the next page. Each push may
            // cascade — later sections shift — so we re-run the loop until
            // stable or we hit the cap.
            function runOnce() {
                var sections = buildSections();
                var changed = false;
                for (var i = 0; i < sections.length; i++) {
                    var s = sections[i];
                    var needsPush = headingIsOrphaned(s.heading)
                        || sectionHasStraddlingFigure(s);
                    if (needsPush) {
                        if (pushToNextPage(s.heading)) changed = true;
                    }
                }
                // Also handle section-less figures (no preceding heading),
                // or the rare case where a figure inside a section is
                // padded individually after its heading also moved.
                var figures = Array.from(document.querySelectorAll(keepWholeSelector));
                figures.forEach(function(fig) {
                    if (fig.closest(keepWholeSelector) !== fig) return; // nested
                    var rect = fig.getBoundingClientRect();
                    var h = rect.height;
                    if (h <= 0 || h >= pageH) return;
                    var absTop = rect.top + window.scrollY;
                    var absBottom = absTop + h;
                    if (pageOf(absTop) === pageOf(absBottom - 1)) return;
                    // Straddling figure not covered by a section push — pad it.
                    if (pushToNextPage(fig)) changed = true;
                });
                return changed;
            }

            var iterations = 0;
            while (runOnce() && iterations < 15) { iterations++; }
        })();
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { _, _ in c.resume() }
        }
    }

    private func makeOffscreenWebView(pageSize: CGSize) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: pageSize),
            configuration: config
        )
        // Force light appearance so `@media (prefers-color-scheme: dark)` rules
        // in the active theme don't fire. PDFs are always printed on white paper.
        webView.appearance = NSAppearance(named: .aqua)
        return webView
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

    private func createPDF(
        from webView: WKWebView,
        pageSize: CGSize,
        sliceHeight: CGFloat,
        verticalMargin: CGFloat
    ) async throws -> Data {
        // Measure content height via JavaScript, then slice the content into
        // `sliceHeight`-tall rects and stitch them into a single PDFDocument.
        // Each captured slice page is then wrapped in a media box of full
        // `pageSize`, vertically centered via a mediaBox offset so the slice
        // appears with `verticalMargin` of whitespace on top and bottom.
        //
        // Note: CSS print-media break rules are NOT honoured — JS-based padding
        // in `applyHeadingOrphanGuard` / `applyBreakInsideAvoidPadding` emulates
        // the most important ones.
        let rawHeight = await withCheckedContinuation { (c: CheckedContinuation<CGFloat, Never>) in
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                if let num = result as? NSNumber {
                    c.resume(returning: CGFloat(truncating: num))
                } else {
                    c.resume(returning: sliceHeight)
                }
            }
        }
        guard rawHeight > 0 else {
            throw PDFExportError.emptyContent
        }
        let totalHeight = max(rawHeight, sliceHeight)
        let pageCount = Int(ceil(totalHeight / sliceHeight))

        let combined = PDFDocument()
        for pageIndex in 0..<pageCount {
            let y = CGFloat(pageIndex) * sliceHeight
            let rect = CGRect(x: 0, y: y, width: pageSize.width, height: sliceHeight)
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
            guard let page = PDFDocument(data: data)?.page(at: 0) else { continue }
            // Expand the page's mediaBox to the full paper size. The captured
            // content lives at (0, 0, pageSize.width, sliceHeight) in PDF user
            // space; shifting the mediaBox origin down by `verticalMargin`
            // leaves that band of whitespace above and below the content.
            let newMediaBox = CGRect(
                x: 0,
                y: -verticalMargin,
                width: pageSize.width,
                height: pageSize.height
            )
            page.setBounds(newMediaBox, for: .mediaBox)
            combined.insert(page, at: combined.pageCount)
        }

        return combined.dataRepresentation() ?? Data()
    }

    /// Draw running header/footer text (title, page numbers) onto each page
    /// using a fresh CGPDF context — the CSS `@top-right`/`@bottom-center`
    /// rules from `makePageCSS` never render under pixel-slicing.
    ///
    /// Returns new PDF data; the input data is discarded.
    private func stampPageChrome(
        pdfData: Data,
        pageSize: CGSize,
        verticalMargin: CGFloat,
        options: PDFExportOptions,
        documentTitle: String
    ) -> Data {
        guard options.showHeader || options.showFooter else { return pdfData }
        guard let srcProvider = CGDataProvider(data: pdfData as CFData),
              let srcPDF = CGPDFDocument(srcProvider),
              srcPDF.numberOfPages > 0
        else { return pdfData }

        let pageCount = srcPDF.numberOfPages
        let headerText = options.headerText ?? documentTitle
        let outData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outData) else { return pdfData }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return pdfData }

        let chromeFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let chromeColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        let chromeAttributes: [NSAttributedString.Key: Any] = [
            .font: chromeFont,
            .foregroundColor: chromeColor,
        ]

        for pageIndex in 1...pageCount {
            guard let srcPage = srcPDF.page(at: pageIndex) else { continue }
            let srcMediaBox = srcPage.getBoxRect(.mediaBox)
            var box = mediaBox
            ctx.beginPage(mediaBox: &box)

            // Redraw the original page into the new page's coordinate system.
            // Shift down so the original page appears at our expected (0, 0, pageSize).
            ctx.saveGState()
            ctx.translateBy(x: -srcMediaBox.origin.x, y: -srcMediaBox.origin.y)
            ctx.drawPDFPage(srcPage)
            ctx.restoreGState()

            // Draw chrome in the margin bands. Skip header on the first page
            // when it's a title page, and never print page 1's number (looks
            // cleaner — standard book convention).
            let isTitlePage = pageIndex == 1
            if options.showHeader, !isTitlePage, !headerText.isEmpty {
                drawChromeText(
                    headerText,
                    attributes: chromeAttributes,
                    pageSize: pageSize,
                    verticalMargin: verticalMargin,
                    position: .header,
                    context: ctx
                )
            }
            if options.showFooter, !isTitlePage {
                drawChromeText(
                    "\(pageIndex)",
                    attributes: chromeAttributes,
                    pageSize: pageSize,
                    verticalMargin: verticalMargin,
                    position: .footer,
                    context: ctx
                )
            }

            ctx.endPage()
        }

        ctx.closePDF()
        return outData as Data
    }

    private enum ChromePosition { case header, footer }

    private func drawChromeText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        pageSize: CGSize,
        verticalMargin: CGFloat,
        position: ChromePosition,
        context: CGContext
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let lineBounds = CTLineGetImageBounds(line, context)

        // Horizontal: centered for footer, right-aligned for header.
        let horizontalPadding: CGFloat = 54
        let x: CGFloat
        switch position {
        case .header:
            x = pageSize.width - horizontalPadding - lineBounds.width
        case .footer:
            x = (pageSize.width - lineBounds.width) / 2
        }

        // Vertical: header sits in top margin band, footer in bottom band.
        let baselineOffset: CGFloat = 12
        let y: CGFloat
        switch position {
        case .header:
            y = pageSize.height - verticalMargin + baselineOffset
        case .footer:
            y = verticalMargin - baselineOffset - lineBounds.height
        }

        context.saveGState()
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
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
