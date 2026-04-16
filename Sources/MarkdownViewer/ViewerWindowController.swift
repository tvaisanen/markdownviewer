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
    private var filesButton: NSButton!
    private var tocButton: NSButton!
    private let renderer = MarkdownRenderer()
    private var templateHTML: String = ""
    let splitViewController = MainSplitViewController()
    var isSidebarPinned = false
    private var sidebarHoverView: SidebarHoverZone?

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
            statusBar.heightAnchor.constraint(equalToConstant: 34),
        ])

        let containerVC = NSViewController()
        containerVC.view = containerView
        containerVC.addChild(splitViewController)

        window.contentViewController = containerVC
        splitViewController.sidebarViewController.delegate = self
        splitViewController.tocViewController.delegate = self
        loadTemplate()

        // Add hover zone on left edge for auto-show sidebar
        let hoverZone = SidebarHoverZone(windowController: self)
        hoverZone.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hoverZone)
        NSLayoutConstraint.activate([
            hoverZone.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hoverZone.topAnchor.constraint(equalTo: containerView.topAnchor),
            hoverZone.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hoverZone.widthAnchor.constraint(equalToConstant: 5),
        ])
        sidebarHoverView = hoverZone

        window.restoreAndTrackFrame()
    }

    private func makeStatusBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true

        let border = NSBox()
        border.boxType = .separator
        border.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(border)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: bar.topAnchor),
            border.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
        ])

        filesButton = Self.makeToggleButton(
            symbolName: "doc.text",
            tooltip: "Files",
            target: self,
            action: #selector(showFilesMode(_:))
        )

        tocButton = Self.makeToggleButton(
            symbolName: "sidebar.leading",
            tooltip: "Table of Contents",
            target: self,
            action: #selector(showTOCMode(_:))
        )

        let modeStack = NSStackView(views: [filesButton, tocButton])
        modeStack.orientation = .horizontal
        modeStack.spacing = 4
        modeStack.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(modeStack)
        NSLayoutConstraint.activate([
            modeStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            modeStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    private static func makeToggleButton(symbolName: String, tooltip: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        button.target = target
        button.action = action
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.wantsLayer = true
        button.layer?.cornerRadius = 3
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 20),
        ])
        return button
    }

    private func updateButtonStates() {
        let filesActive = splitViewController.currentMode == .files && !isSidebarCollapsed
        let tocActive = splitViewController.currentMode == .toc && !isSidebarCollapsed

        filesButton.layer?.backgroundColor = filesActive
            ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : nil
        filesButton.contentTintColor = filesActive ? .labelColor : .secondaryLabelColor

        tocButton.layer?.backgroundColor = tocActive
            ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : nil
        tocButton.contentTintColor = tocActive ? .labelColor : .secondaryLabelColor
    }

    @objc private func showFilesMode(_ sender: Any?) {
        if splitViewController.currentMode == .files && !isSidebarCollapsed {
            isSidebarPinned = false
            collapseSidebar()
        } else {
            splitViewController.switchSidebar(to: .files)
            isSidebarPinned = true
            expandSidebar()
        }
        updateButtonStates()
    }

    @objc private func showTOCMode(_ sender: Any?) {
        if splitViewController.currentMode == .toc && !isSidebarCollapsed {
            isSidebarPinned = false
            collapseSidebar()
        } else {
            splitViewController.switchSidebar(to: .toc)
            isSidebarPinned = true
            expandSidebar()
            updateTOC()
        }
        updateButtonStates()
    }

    func toggleSidebar() {
        if isSidebarCollapsed {
            isSidebarPinned = true
            expandSidebar()
        } else {
            isSidebarPinned = false
            collapseSidebar()
        }
        updateButtonStates()
    }

    private var isSidebarCollapsed: Bool {
        splitViewController.splitViewItems.first?.isCollapsed ?? true
    }

    private func collapseSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            splitViewController.splitViewItems.first?.animator().isCollapsed = true
        }
    }

    private func expandSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            splitViewController.splitViewItems.first?.animator().isCollapsed = false
        }
    }

    func sidebarHoverEntered() {
        guard isSidebarCollapsed && !isSidebarPinned else { return }
        expandSidebar()
        updateButtonStates()
    }

    func sidebarHoverExited() {
        guard !isSidebarCollapsed && !isSidebarPinned else { return }
        collapseSidebar()
        updateButtonStates()
    }

    private func updateTOC() {
        guard selectedIndex >= 0 && selectedIndex < openFiles.count else { return }
        let url = openFiles[selectedIndex].url
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return }
        let headings = HeadingExtractor.extract(from: markdown)
        splitViewController.tocViewController.updateHeadings(headings)
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

    // MARK: - Recent Files

    private static let recentFilesKey = "RecentFiles"
    private static let maxRecentFilesKey = "MaxRecentFiles"

    private var maxRecentFiles: Int {
        let val = UserDefaults.standard.integer(forKey: Self.maxRecentFilesKey)
        return val > 0 ? val : 10
    }

    private func addToRecent(url: URL) {
        var recents = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) ?? []
        let path = url.path
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        if recents.count > maxRecentFiles {
            recents = Array(recents.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(recents, forKey: Self.recentFilesKey)
    }

    func restoreRecentFiles() {
        guard let recents = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) else { return }
        for path in recents.reversed() {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                openFile(url: url)
            }
        }
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
        addToRecent(url: url)
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

        if splitViewController.currentMode == .toc {
            updateTOC()
        }
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

    func applyMermaidTheme(_ theme: String) {
        splitViewController.contentViewController.webContentView.setMermaidTheme(theme)
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

// MARK: - TOCDelegate

extension ViewerWindowController: TOCDelegate {
    func tocDidSelectHeading(_ heading: Heading) {
        splitViewController.contentViewController.webContentView.scrollToHeading(text: heading.text, level: heading.level)
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

// MARK: - Sidebar Hover Zone

/// Invisible view on the left edge that triggers sidebar auto-show on hover.
/// Also monitors mouse movement to auto-hide when leaving the sidebar area.
final class SidebarHoverZone: NSView {

    private weak var windowController: ViewerWindowController?
    private var edgeTrackingArea: NSTrackingArea?
    private var monitor: Any?

    init(windowController: ViewerWindowController) {
        self.windowController = windowController
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = edgeTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        edgeTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        windowController?.sidebarHoverEntered()
        startMonitoringMouseExit()
    }

    private func startMonitoringMouseExit() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkMousePosition(event)
            return event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func checkMousePosition(_ event: NSEvent) {
        guard let wc = windowController,
              let window = wc.window,
              let contentView = window.contentView,
              !wc.isSidebarPinned else {
            stopMonitoring()
            return
        }

        let sidebarItem = wc.splitViewController.splitViewItems.first
        guard let sidebarView = sidebarItem?.viewController.view,
              !(sidebarItem?.isCollapsed ?? true) else {
            stopMonitoring()
            return
        }

        let mouseInWindow = event.locationInWindow
        let mouseInContent = contentView.convert(mouseInWindow, from: nil)
        let sidebarFrame = sidebarView.convert(sidebarView.bounds, to: contentView)

        // Add some padding so it doesn't flicker
        let hitRect = sidebarFrame.insetBy(dx: -10, dy: -10)
        if !hitRect.contains(mouseInContent) {
            stopMonitoring()
            wc.sidebarHoverExited()
        }
    }

    deinit {
        stopMonitoring()
    }
}
