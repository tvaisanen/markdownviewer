import Foundation

public final class PlantUMLRenderer: Sendable {

    private let binaryPath: String
    private let timeout: TimeInterval

    public init(binaryPath: String? = nil, timeout: TimeInterval = 10.0) {
        self.binaryPath = binaryPath ?? PlantUMLRenderer.findBinary() ?? "/opt/homebrew/bin/plantuml"
        self.timeout = timeout
    }

    public func render(source: String) -> String {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            return placeholder()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-tsvg", "-pipe"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return errorDiv("Failed to launch plantuml: \(error.localizedDescription)")
        }

        let inputData = source.data(using: .utf8) ?? Data()
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()

        // Timeout via dispatch
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }

        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            process.terminate()
            return errorDiv("PlantUML rendering timed out after \(Int(timeout))s")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
              let svg = String(data: outputData, encoding: .utf8),
              !svg.isEmpty else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            return errorDiv("PlantUML error: \(errMsg)")
        }

        return svg
    }

    private func placeholder() -> String {
        return """
        <div class="plantuml-placeholder">
            PlantUML not installed.<br>
            Run: <code>brew install plantuml</code>
        </div>
        """
    }

    private func errorDiv(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <div class="plantuml-error">
            \(escaped)
        </div>
        """
    }

    private static func findBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/plantuml",
            "/usr/local/bin/plantuml",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
