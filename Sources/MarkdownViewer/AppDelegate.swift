import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [URL: ViewerWindowController] = [:]
    private var appearanceObservation: NSKeyValueObservation?

    private var openedViaAppleEvent = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearanceChanges()

        // Handle command-line arguments (files passed via --args or direct invocation)
        let args = CommandLine.arguments.dropFirst() // skip executable path
        let fileURLs = args
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        if !fileURLs.isEmpty {
            openFiles(urls: fileURLs)
        } else if !openedViaAppleEvent {
            // No files from CLI or Apple Events — show open panel
            showOpenPanel()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        openedViaAppleEvent = true
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        openFiles(urls: urls)
        application.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showOpenPanel()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - File opening

    private func openFiles(urls: [URL]) {
        for url in urls {
            openFile(url: url)
        }
    }

    private func openFile(url: URL) {
        // Already open? Bring to front.
        if let existing = windowControllers[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(fileURL: url)

        // Tab into existing window if one exists
        if let existingWindow = windowControllers.values.first?.window,
           let newWindow = controller.window {
            existingWindow.addTabbedWindow(newWindow, ordered: .above)
        }

        controller.window?.makeKeyAndOrderFront(nil)
        windowControllers[url] = controller

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.windowControllers = self?.windowControllers.filter { $0.value.window !== window } ?? [:]
            }
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            openFiles(urls: panel.urls)
        }
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MarkdownViewer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MarkdownViewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Show All Windows", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    // MARK: - Dark mode

    private func observeAppearanceChanges() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.windowControllers.values.forEach { $0.updateMermaidTheme(isDark: isDark) }
            }
        }
    }
}
