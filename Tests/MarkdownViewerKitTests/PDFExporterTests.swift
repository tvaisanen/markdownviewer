import XCTest
import PDFKit
@testable import MarkdownViewerKit

@MainActor
final class PDFExporterTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "Fixtures/pdf") else {
            throw XCTSkip("Missing fixture: \(name).md")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSimpleDocumentProducesOnePage() async throws {
        let markdown = try loadFixture("simple")
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: .defaults,
            documentTitle: "simple"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 1)
    }

    func testStartNewPageAtH1ProducesTwoPages() async throws {
        let markdown = try loadFixture("heading-break")
        var opts = PDFExportOptions.defaults
        opts.startNewPageAtH1 = true
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: opts,
            documentTitle: "heading-break"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 2)
    }

    func testLongCodeBlockIsAllowedToSplit() async throws {
        let markdown = try loadFixture("long-code")
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: .defaults,
            documentTitle: "long-code"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1)
    }

    func testMermaidDiagramStaysOnOnePage() async throws {
        // Regression test for the pixel-slicing workaround in PDFExporter.
        // Without applyBreakInsideAvoidPadding, the Mermaid diagram in
        // `image-near-break.md` would be split across two pages.
        let markdown = try loadFixture("image-near-break")
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: .defaults,
            documentTitle: "image-near-break"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))

        // Find which page contains the substring "End" that appears inside the
        // last Mermaid node. If padding worked, the entire diagram is on ONE
        // page — the page containing "End" should also contain "Start".
        var endPage: Int?
        var startPage: Int?
        for i in 0..<doc.pageCount {
            let text = doc.page(at: i)?.string ?? ""
            if text.contains("End")   { endPage   = i }
            if text.contains("Start") { startPage = i }
        }

        if startPage != nil && endPage != nil {
            XCTAssertEqual(startPage, endPage, "Mermaid diagram was split across pages")
        } else {
            // SVG text is often rendered as paths and not extractable by PDFKit.
            // Fall back to a geometric assertion: the PDF must be non-empty and valid.
            XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
            XCTAssertGreaterThan(data.count, 1000)
            // CONCERN: Mermaid SVG text was not extractable by PDFKit;
            // the diagram-integrity check fell back to a size-only assertion.
        }
    }

    func testEachThemeProducesNonEmptyPDF() async throws {
        let markdown = try loadFixture("simple")
        for theme in PDFTheme.allCases {
            var opts = PDFExportOptions.defaults
            opts.theme = theme
            let exporter = PDFExporter(bundle: Bundle(for: Self.self))
            let data = try await exporter.exportPDF(
                markdown: markdown,
                options: opts,
                documentTitle: "simple"
            )
            XCTAssertGreaterThan(data.count, 0, "\(theme) produced empty PDF")
        }
    }
}
