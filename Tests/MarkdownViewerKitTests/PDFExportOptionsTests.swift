import XCTest
@testable import MarkdownViewerKit

final class PDFExportOptionsTests: XCTestCase {

    func testDefaultOptionsUseGitHubTheme() {
        let opts = PDFExportOptions.defaults
        XCTAssertEqual(opts.theme, .gitHub)
        XCTAssertEqual(opts.orientation, .portrait)
        XCTAssertFalse(opts.startNewPageAtH1)
        XCTAssertTrue(opts.showHeader)
        XCTAssertTrue(opts.showFooter)
    }

    func testPaperSizeLetterDimensionsInPoints() {
        let size = PDFExportOptions.PaperSize.letter.pointSize
        // 8.5in x 11in at 72 dpi
        XCTAssertEqual(size.width, 612, accuracy: 0.5)
        XCTAssertEqual(size.height, 792, accuracy: 0.5)
    }

    func testPaperSizeA4DimensionsInPoints() {
        let size = PDFExportOptions.PaperSize.a4.pointSize
        // 210mm x 297mm at 72 dpi
        XCTAssertEqual(size.width, 595, accuracy: 1.0)
        XCTAssertEqual(size.height, 842, accuracy: 1.0)
    }

    func testOrientationLandscapeSwapsDimensions() {
        let portrait = PDFExportOptions.PaperSize.letter.pointSize(orientation: .portrait)
        let landscape = PDFExportOptions.PaperSize.letter.pointSize(orientation: .landscape)
        XCTAssertEqual(portrait.width, landscape.height, accuracy: 0.5)
        XCTAssertEqual(portrait.height, landscape.width, accuracy: 0.5)
    }
}
