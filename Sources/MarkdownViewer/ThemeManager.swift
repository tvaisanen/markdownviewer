import Foundation
import MarkdownViewerKit

@MainActor
final class ThemeManager {

    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")
    private static let defaultsKey = "DocumentTheme"

    private init() {}

    var current: PDFTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
               let theme = PDFTheme(rawValue: raw) {
                return theme
            }
            return .gitHub
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: newValue)
        }
    }
}
