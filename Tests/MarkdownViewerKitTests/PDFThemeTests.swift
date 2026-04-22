import XCTest
@testable import MarkdownViewerKit

final class PDFThemeTests: XCTestCase {

    func testEachThemeHasUniqueStylesheetName() {
        let names = Set(PDFTheme.allCases.map(\.stylesheetFilename))
        XCTAssertEqual(names.count, PDFTheme.allCases.count)
    }

    func testStylesheetFilenamesMatchResources() {
        XCTAssertEqual(PDFTheme.gitHub.stylesheetFilename,    "github.css")
        XCTAssertEqual(PDFTheme.technical.stylesheetFilename, "technical.css")
        XCTAssertEqual(PDFTheme.appleDocs.stylesheetFilename, "appledocs.css")
    }

    func testDisplayNameIsHumanReadable() {
        XCTAssertEqual(PDFTheme.gitHub.displayName,    "GitHub")
        XCTAssertEqual(PDFTheme.technical.displayName, "Technical Paper")
        XCTAssertEqual(PDFTheme.appleDocs.displayName, "Apple Documentation")
    }

    func testDefaultChromeDiffersByTheme() {
        // Spec: technical → header+footer, appleDocs → footer only, github → none
        XCTAssertTrue(PDFTheme.technical.defaultShowHeader)
        XCTAssertTrue(PDFTheme.technical.defaultShowFooter)

        XCTAssertFalse(PDFTheme.appleDocs.defaultShowHeader)
        XCTAssertTrue(PDFTheme.appleDocs.defaultShowFooter)

        XCTAssertFalse(PDFTheme.gitHub.defaultShowHeader)
        XCTAssertFalse(PDFTheme.gitHub.defaultShowFooter)
    }
}
