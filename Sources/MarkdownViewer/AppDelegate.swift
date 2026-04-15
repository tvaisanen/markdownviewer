import Cocoa

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [URL: ViewerWindowController] = [:]
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearanceChanges()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ensure we receive openFiles calls
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
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
