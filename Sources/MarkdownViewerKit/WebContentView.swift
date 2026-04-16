import Cocoa
import WebKit

public final class WebContentView: NSView, WKNavigationDelegate {

    private let webView: WKWebView
    private var pendingScrollY: Double = 0
    private var currentBrightness: Double = 1.0
    private var currentMermaidTheme: String?
    private var pageLoaded = false

    public override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        setupWebView()
    }

    required init?(coder: NSCoder) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(coder: coder)
        setupWebView()
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.appearance = NSAppearance(named: .aqua)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    /// Load rendered HTML, preserving scroll position.
    public func loadHTML(_ html: String, baseURL: URL?) {
        // Save current scroll position before reload
        webView.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
            if let scrollY = result as? Double {
                self?.pendingScrollY = scrollY
            }
            self?.webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    /// Load HTML for the first time (no scroll preservation).
    public func loadInitialHTML(_ html: String, baseURL: URL?) {
        pendingScrollY = 0
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Set the Mermaid theme. Applied immediately if page is loaded, otherwise queued.
    public func setMermaidTheme(_ theme: String) {
        currentMermaidTheme = theme
        guard pageLoaded else { return }
        webView.evaluateJavaScript("setMermaidTheme('\(theme)')") { _, _ in }
    }

    /// Scroll to a heading in the rendered content.
    public func scrollToHeading(text: String, level: Int) {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        let js = """
        (function() {
            const headings = document.querySelectorAll('h\(level)');
            for (const h of headings) {
                if (h.textContent.trim() === '\(escapedText)') {
                    h.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    break;
                }
            }
        })();
        """
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Set content brightness (0.3–1.0).
    public func setBrightness(_ value: Double) {
        currentBrightness = max(0.3, min(1.0, value))
        guard pageLoaded else { return }
        applyBrightness()
    }

    private func applyBrightness() {
        webView.evaluateJavaScript("document.documentElement.style.filter = 'brightness(\(currentBrightness))'") { _, _ in }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true

        if pendingScrollY > 0 {
            let scrollY = pendingScrollY
            pendingScrollY = 0
            webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))") { _, _ in }
        }

        applyBrightness()

        if let theme = currentMermaidTheme {
            webView.evaluateJavaScript("setMermaidTheme('\(theme)')") { _, _ in }
        }
    }
}
