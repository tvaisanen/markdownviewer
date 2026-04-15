import Cocoa
import WebKit

public final class WebContentView: NSView, WKNavigationDelegate {

    private let webView: WKWebView
    private var pendingScrollY: Double = 0

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

    /// Set the Mermaid theme via JS.
    public func setMermaidTheme(_ theme: String) {
        webView.evaluateJavaScript("setMermaidTheme('\(theme)')") { _, error in
            if let error {
                print("Mermaid theme error: \(error)")
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pendingScrollY > 0 else { return }
        let scrollY = pendingScrollY
        pendingScrollY = 0
        webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))") { _, _ in }
    }
}
