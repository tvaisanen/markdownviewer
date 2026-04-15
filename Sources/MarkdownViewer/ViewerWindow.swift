import Cocoa

final class ViewerWindow: NSWindow {

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 1000, height: 700)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.tabbingMode = .disallowed
        self.title = "MarkdownViewer"
        self.setFrameAutosaveName("MarkdownViewerWindow")
        if !self.setFrameUsingName("MarkdownViewerWindow") {
            self.center()
        }
    }
}
