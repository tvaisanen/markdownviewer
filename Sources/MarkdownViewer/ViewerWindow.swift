import Cocoa

final class ViewerWindow: NSWindow {

    private static let frameName = "ViewerWindow"

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 794, height: 980),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.tabbingMode = .disallowed
        self.title = "MarkdownViewer"
        self.contentMinSize = NSSize(width: 400, height: 300)
    }

    /// Restore saved frame and begin tracking changes.
    /// Call after the window's content view hierarchy is fully set up.
    func restoreAndTrackFrame() {
        if !setFrameUsingName(Self.frameName) {
            setContentSize(NSSize(width: 794, height: 980))
            center()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameSave),
            name: NSWindow.didResizeNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameSave),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc func frameSave() {
        saveFrame(usingName: Self.frameName)
    }
}
