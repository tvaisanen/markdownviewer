import Cocoa
import MarkdownViewerKit

final class ViewerWindowController: NSWindowController {

    let fileURL: URL
    private let contentView = WebContentView(frame: .zero)
    private let fileWatcher = FileWatcher()
    private let renderer = MarkdownRenderer()
    private var templateHTML: String = ""
    private var isFirstLoad = true

    init(fileURL: URL) {
        self.fileURL = fileURL
        let window = ViewerWindow(for: fileURL)
        super.init(window: window)
        window.contentView = contentView
        loadTemplate()
        loadFile()
        startWatching()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func loadTemplate() {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "html"),
              let html = try? String(contentsOf: templateURL, encoding: .utf8) else {
            templateHTML = "<html><body>{{CONTENT}}</body></html>"
            return
        }
        templateHTML = html
    }

    private func loadFile() {
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let html = renderer.renderFull(markdown: markdown, templateHTML: templateHTML)
        let resourcesURL = Bundle.main.resourceURL

        if isFirstLoad {
            isFirstLoad = false
            contentView.loadInitialHTML(html, baseURL: resourcesURL)
        } else {
            contentView.loadHTML(html, baseURL: resourcesURL)
        }
    }

    private func startWatching() {
        fileWatcher.onChange = { [weak self] in
            self?.loadFile()
        }
        fileWatcher.watch(path: fileURL.path)
    }

    func updateMermaidTheme(isDark: Bool) {
        contentView.setMermaidTheme(isDark ? "dark" : "default")
    }
}
