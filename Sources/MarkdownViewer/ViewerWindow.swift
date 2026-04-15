import Cocoa

final class ViewerWindow: NSWindow {

    init(for fileURL: URL) {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.tabbingMode = .preferred
        self.title = fileURL.lastPathComponent
        self.center()
        self.setFrameAutosaveName("MarkdownViewerWindow")
    }
}
