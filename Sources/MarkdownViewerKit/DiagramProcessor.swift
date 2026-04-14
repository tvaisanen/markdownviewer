import Foundation

public enum DiagramType: Sendable {
    case mermaid
    case plantuml
}

public struct DiagramBlock: Sendable {
    public let id: String
    public let type: DiagramType
    public let source: String
}

public struct ExtractionResult: Sendable {
    public let processedMarkdown: String
    public let blocks: [DiagramBlock]
}

public enum DiagramProcessor {

    private static let fencePattern = try! NSRegularExpression(
        pattern: "```(mermaid|plantuml)\\n([\\s\\S]*?)\\n```",
        options: []
    )

    public static func extractDiagrams(from markdown: String) -> ExtractionResult {
        let nsRange = NSRange(markdown.startIndex..., in: markdown)
        let matches = fencePattern.matches(in: markdown, range: nsRange)

        var blocks: [DiagramBlock] = []
        var result = markdown

        // Process matches in reverse so ranges stay valid
        for match in matches.reversed() {
            guard let typeRange = Range(match.range(at: 1), in: markdown),
                  let sourceRange = Range(match.range(at: 2), in: markdown),
                  let fullRange = Range(match.range, in: markdown) else { continue }

            let typeString = String(markdown[typeRange])
            let source = String(markdown[sourceRange])
            let type: DiagramType = typeString == "mermaid" ? .mermaid : .plantuml
            let id = UUID().uuidString

            blocks.insert(DiagramBlock(id: id, type: type, source: source), at: 0)
            result.replaceSubrange(fullRange, with: "<!--DIAGRAM:\(id)-->")
        }

        return ExtractionResult(processedMarkdown: result, blocks: blocks)
    }

    public static func injectDiagrams(
        into html: String,
        renderedBlocks: [String: String]
    ) -> String {
        var result = html
        for (id, rendered) in renderedBlocks {
            result = result.replacingOccurrences(of: "<!--DIAGRAM:\(id)-->", with: rendered)
        }
        return result
    }
}
