import Foundation
import CoreGraphics

public struct PDFExportOptions: Equatable, Sendable {

    public enum Orientation: String, Equatable, Sendable, CaseIterable {
        case portrait
        case landscape
    }

    public enum PaperSize: String, Equatable, Sendable, CaseIterable {
        case letter
        case a4

        /// Base portrait dimensions in PDF points (1pt = 1/72in).
        public var pointSize: CGSize {
            switch self {
            case .letter: return CGSize(width: 612, height: 792)   // 8.5 x 11 in
            case .a4:     return CGSize(width: 595, height: 842)   // 210 x 297 mm
            }
        }

        public func pointSize(orientation: Orientation) -> CGSize {
            let base = pointSize
            switch orientation {
            case .portrait:  return base
            case .landscape: return CGSize(width: base.height, height: base.width)
            }
        }
    }

    /// Document theme applied to both screen rendering and the exported PDF.
    public var theme: PDFTheme
    /// Paper size for the exported PDF.
    public var paperSize: PaperSize
    /// Page orientation for the exported PDF.
    public var orientation: Orientation
    /// When true, every top-level H1 heading starts on a fresh page. Default false.
    public var startNewPageAtH1: Bool
    /// Whether to render a running header on each page.
    public var showHeader: Bool
    /// Whether to render a running footer (page number) on each page.
    public var showFooter: Bool
    /// Running header text; nil = use theme default behavior.
    public var headerText: String?

    public init(
        theme: PDFTheme = .gitHub,
        paperSize: PaperSize = .letter,
        orientation: Orientation = .portrait,
        startNewPageAtH1: Bool = false,
        showHeader: Bool = true,
        showFooter: Bool = true,
        headerText: String? = nil
    ) {
        self.theme = theme
        self.paperSize = paperSize
        self.orientation = orientation
        self.startNewPageAtH1 = startNewPageAtH1
        self.showHeader = showHeader
        self.showFooter = showFooter
        self.headerText = headerText
    }

    public static let defaults = PDFExportOptions()
}
