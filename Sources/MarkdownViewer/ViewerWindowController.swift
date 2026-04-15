import Cocoa
import MarkdownViewerKit

@MainActor
final class ViewerWindowController: NSWindowController {

    private struct OpenFile {
        let url: URL
        let watcher: FileWatcher
        var isStale: Bool = false
    }

    private var openFiles: [OpenFile] = []
    private var selectedIndex: Int = -1
    private let renderer = MarkdownRenderer()
    private var templateHTML: String = ""
    private let splitViewController = MainSplitViewController()

    init() {
        let window = ViewerWindow()
        super.init(window: window)

        // Build container: split view + bottom status bar
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let splitView = splitViewController.view
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = makeStatusBar()

        containerView.addSubview(splitView)
        containerView.addSubview(statusBar)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        let containerVC = NSViewController()
        containerVC.view = containerView
        containerVC.addChild(splitViewController)

        window.contentViewController = containerVC
        splitViewController.sidebarViewController.delegate = self
        loadTemplate()
    }

    private func makeStatusBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true

        // Top border
        let border = NSBox()
        border.boxType = .separator
        border.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(border)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: bar.topAnchor),
            border.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
        ])

        let sidebarToggle = NSButton(
            image: NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Toggle Sidebar")!,
            target: nil,
            action: #selector(NSSplitViewController.toggleSidebar(_:))
        )
        sidebarToggle.bezelStyle = .accessoryBarAction
        sidebarToggle.isBordered = false
        sidebarToggle.toolTip = "Toggle Sidebar (⌃⌘S)"
        sidebarToggle.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(sidebarToggle)
        NSLayoutConstraint.activate([
            sidebarToggle.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            sidebarToggle.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
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

    // MARK: - File Management

    func openFile(url: URL) {
        // Already open? Just select it.
        if let existingIndex = openFiles.firstIndex(where: { $0.url == url }) {
            selectFile(at: existingIndex)
            return
        }

        let watcher = FileWatcher()
        let fileIndex = openFiles.count

        watcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.fileDidChange(at: url)
            }
        }
        watcher.watch(path: url.path)

        openFiles.append(OpenFile(url: url, watcher: watcher))
        refreshSidebar()
        selectFile(at: fileIndex)
    }

    func closeFile(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        openFiles[index].watcher.stop()
        openFiles.remove(at: index)

        if openFiles.isEmpty {
            selectedIndex = -1
            splitViewController.contentViewController.showEmptyState()
            window?.title = "MarkdownViewer"
        } else {
            let newIndex = min(index, openFiles.count - 1)
            selectFile(at: newIndex)
        }

        refreshSidebar()
    }

    private func selectFile(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        selectedIndex = index
        splitViewController.sidebarViewController.selectRow(index)

        if openFiles[index].isStale {
            openFiles[index].isStale = false
        }

        renderSelectedFile()
        window?.title = openFiles[index].url.lastPathComponent
    }

    private func renderSelectedFile() {
        guard selectedIndex >= 0 && selectedIndex < openFiles.count else { return }
        let url = openFiles[selectedIndex].url
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return }
        let html = renderer.renderFull(markdown: markdown, templateHTML: templateHTML)
        let resourcesURL = Bundle.main.resourceURL
        let contentVC = splitViewController.contentViewController
        contentVC.showContent()
        contentVC.webContentView.loadHTML(html, baseURL: resourcesURL)
    }

    private func fileDidChange(at url: URL) {
        guard let index = openFiles.firstIndex(where: { $0.url == url }) else { return }
        if index == selectedIndex {
            renderSelectedFile()
        } else {
            openFiles[index].isStale = true
        }
    }

    private func refreshSidebar() {
        let items = openFiles.map { file -> SidebarViewController.FileItem in
            let filename = file.url.lastPathComponent
            let parentDir = file.url.deletingLastPathComponent().path
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return SidebarViewController.FileItem(filename: filename, parentDirectory: parentDir)
        }
        splitViewController.sidebarViewController.updateFiles(items)
    }

    func updateMermaidTheme(isDark: Bool) {
        splitViewController.contentViewController.webContentView.setMermaidTheme(isDark ? "dark" : "default")
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                openFile(url: url)
            }
        }
    }
}

// MARK: - SidebarDelegate

extension ViewerWindowController: SidebarDelegate {
    func sidebarDidSelectFile(at index: Int) {
        selectFile(at: index)
    }

    func sidebarDidRequestCloseFile(at index: Int) {
        closeFile(at: index)
    }

    func sidebarDidRequestOpenFile() {
        showOpenPanel()
    }
}
