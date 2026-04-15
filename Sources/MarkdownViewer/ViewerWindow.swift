import Cocoa

final class ViewerWindow: NSWindow {

    private static let frameKey = "ViewerWindowFrame"

    init() {
        let savedFrame = Self.loadFrame()
        let contentRect = savedFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.tabbingMode = .disallowed
        self.title = "MarkdownViewer"

        if savedFrame != nil {
            self.setFrame(contentRect, display: false)
        } else {
            self.center()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc private func windowDidResize(_ notification: Notification) {
        persistFrame()
    }

    @objc private func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        let f = frame
        let frameString = "\(f.origin.x) \(f.origin.y) \(f.size.width) \(f.size.height)"
        UserDefaults.standard.set(frameString, forKey: Self.frameKey)
    }

    private static func loadFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let parts = frameString.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let rect = NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])

        // Validate the frame is on a visible screen
        let isOnScreen = NSScreen.screens.contains { $0.frame.intersects(rect) }
        return isOnScreen ? rect : nil
    }
}
