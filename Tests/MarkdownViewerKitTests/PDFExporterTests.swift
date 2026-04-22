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
