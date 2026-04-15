import Foundation

public struct Heading: Sendable {
    public let level: Int
    public let text: String

    public init(level: Int, text: String) {
        self.level = level
        self.text = text
    }
}

public enum HeadingExtractor {

    public static func extract(from markdown: String) -> [Heading] {
        var headings: [Heading] = []
        var inCodeBlock = false

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock { continue }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                guard level >= 1 && level <= 6 else { continue }
                let afterHashes = trimmed.dropFirst(level)
                guard afterHashes.first == " " else { continue }
                let text = String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces)
                headings.append(Heading(level: level, text: text))
            }
        }

        return headings
    }
}
