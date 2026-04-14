import Foundation

public enum MermaidRenderer {

    public static func render(source: String) -> String {
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let bodyContent = source.replacingOccurrences(of: "<", with: "&lt;")

        return """
        <div class="mermaid" data-source="\(escapedSource)">
        \(bodyContent)
        </div>
        """
    }
}
