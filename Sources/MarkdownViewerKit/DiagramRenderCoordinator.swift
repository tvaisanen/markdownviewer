import Foundation
import WebKit

@MainActor
public final class DiagramRenderCoordinator {

    public enum WaitResult {
        case ready
        case timedOut
    }

    /// Polls the page for Mermaid render completion. Returns `.ready` when
    /// every `.mermaid` element has a `data-processed="true"` attribute, or
    /// `.timedOut` after `timeout` seconds.
    public static func waitForDiagrams(
        in webView: WKWebView,
        timeout: TimeInterval = 10
    ) async -> WaitResult {
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval: UInt64 = 100_000_000   // 0.1s in ns

        while Date() < deadline {
            let done = await diagramsReady(in: webView)
            if done { return .ready }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return .timedOut
    }

    private static func diagramsReady(in webView: WKWebView) async -> Bool {
        let js = """
        (function() {
            var els = document.querySelectorAll('.mermaid');
            if (els.length === 0) return true;
            for (var i = 0; i < els.length; i++) {
                if (els[i].getAttribute('data-processed') !== 'true') return false;
            }
            return true;
        })();
        """
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: (result as? Bool) ?? false)
            }
        }
    }
}
