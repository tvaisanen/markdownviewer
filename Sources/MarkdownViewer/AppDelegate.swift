import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private static let mermaidThemeKey = "MermaidTheme"

    private let windowController = ViewerWindowController()
    private var appearanceObservation: NSKeyValueObservation?
    private var openedViaAppleEvent = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.window?.makeKeyAndOrderFront(nil)

        observeAppearanceChanges()
        applyMermaidTheme()

        // Handle command-line arguments
        let args = CommandLine.arguments.dropFirst()
        let fileURLs = args
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        if fileURLs.isEmpty {
            windowController.restoreRecentFiles()
        } else {
            for url in fileURLs {
                windowController.openFile(url: url)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        openedViaAppleEvent = true
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        for url in urls {
            windowController.openFile(url: url)
        }
        windowController.window?.makeKeyAndOrderFront(nil)
        application.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        (windowController.window as? ViewerWindow)?.frameSave()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
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
        fileMenu.addItem(withTitle: "Close File", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "s")
        toggleSidebarItem.keyEquivalentModifierMask = [.command, .control]
        toggleSidebarItem.target = self
        viewMenu.addItem(toggleSidebarItem)

        viewMenu.addItem(.separator())

        let mermaidMenuItem = NSMenuItem(title: "Mermaid Theme", action: nil, keyEquivalent: "")
        let mermaidMenu = NSMenu(title: "Mermaid Theme")
        for theme in ["Auto", "Default", "Dark", "Forest", "Neutral", "Base"] {
            let item = NSMenuItem(title: theme, action: #selector(selectMermaidTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.lowercased()
            mermaidMenu.addItem(item)
        }
        mermaidMenuItem.submenu = mermaidMenu
        viewMenu.addItem(mermaidMenuItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openDocument(_ sender: Any?) {
        windowController.showOpenPanel()
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        windowController.toggleSidebar()
    }

    // MARK: - Mermaid Theme

    @objc private func selectMermaidTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? String else { return }
        UserDefaults.standard.set(theme, forKey: Self.mermaidThemeKey)
        applyMermaidTheme()
    }

    private var selectedMermaidTheme: String {
        UserDefaults.standard.string(forKey: Self.mermaidThemeKey) ?? "auto"
    }

    private func applyMermaidTheme() {
        let theme: String
        if selectedMermaidTheme == "auto" {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            theme = isDark ? "dark" : "default"
        } else {
            theme = selectedMermaidTheme
        }
        windowController.applyMermaidTheme(theme)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectMermaidTheme(_:)),
           let theme = menuItem.representedObject as? String {
            menuItem.state = (theme == selectedMermaidTheme) ? .on : .off
        }
        return true
    }

    // MARK: - Dark mode

    private func observeAppearanceChanges() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyMermaidTheme()
            }
        }
    }
}
