import XCTest
@testable import MarkdownViewerKit

final class PlantUMLRendererTests: XCTestCase {

    func testPlaceholderWhenBinaryNotFound() {
        let renderer = PlantUMLRenderer(binaryPath: "/nonexistent/plantuml")
        let result = renderer.render(source: "@startuml\nA -> B\n@enduml")
        XCTAssertTrue(result.contains("plantuml-placeholder"))
        XCTAssertTrue(result.contains("brew install plantuml"))
    }

    func testRenderProducesSVG() throws {
        // Skip if plantuml is not installed
        let whichResult = shell("which", "plantuml")
        try XCTSkipIf(whichResult == nil, "plantuml not installed")

        let renderer = PlantUMLRenderer()
        let result = renderer.render(source: "@startuml\nAlice -> Bob: Hello\n@enduml")
        XCTAssertTrue(result.contains("<svg"), "Expected SVG output, got: \(result.prefix(200))")
    }

    func testRenderErrorOnInvalidSource() throws {
        let whichResult = shell("which", "plantuml")
        try XCTSkipIf(whichResult == nil, "plantuml not installed")

        // PlantUML handles invalid syntax gracefully — still produces SVG with error
        let renderer = PlantUMLRenderer()
        let result = renderer.render(source: "@startuml\n!invalid_syntax_that_errors\n@enduml")
        // Should still return something (either SVG with error or error div)
        XCTAssertFalse(result.isEmpty)
    }

    private func shell(_ args: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
