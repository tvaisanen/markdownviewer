import Foundation

public enum PDFTheme: String, Equatable, Sendable, CaseIterable {
    case technical
    case appleDocs
    case gitHub

    public var displayName: String {
        switch self {
        case .technical: return "Technical Paper"
        case .appleDocs: return "Apple Documentation"
        case .gitHub:    return "GitHub"
        }
    }

    /// Filename inside `Resources/themes/`.
    public var stylesheetFilename: String {
        switch self {
        case .technical: return "technical.css"
        case .appleDocs: return "appledocs.css"
        case .gitHub:    return "github.css"
        }
    }

    public var defaultShowHeader: Bool {
        switch self {
        case .technical: return true
        case .appleDocs: return false
        case .gitHub:    return false
        }
    }

    public var defaultShowFooter: Bool {
        switch self {
        case .technical: return true
        case .appleDocs: return true
        case .gitHub:    return false
        }
    }
}
