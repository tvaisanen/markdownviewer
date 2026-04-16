import Foundation

let version = "0.1.0"

let usage = """
    mdview — open Markdown files in MarkdownViewer

    USAGE
        mdview [file ...]
        mdview --help | -h
        mdview --version | -v

    EXAMPLES
        mdview                     Launch or activate MarkdownViewer
        mdview README.md           Open a file
        mdview doc1.md doc2.md     Open multiple files
    """

func main() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())

    if args.contains("--help") || args.contains("-h") {
        print(usage)
        return 0
    }

    if args.contains("--version") || args.contains("-v") {
        print("mdview \(version)")
        return 0
    }

    // Validate all files exist before launching
    let files = args.map { ($0, (($0 as NSString).expandingTildeInPath as NSString).standardizingPath) }
    for (original, resolved) in files {
        if !FileManager.default.fileExists(atPath: resolved) {
            fputs("error: file not found: \(original)\n", stderr)
            return 1
        }
    }

    // Build the open command
    var openArgs = ["-a", "MarkdownViewer"]
    for (_, resolved) in files {
        openArgs.append(resolved)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = openArgs

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fputs("error: failed to launch MarkdownViewer: \(error.localizedDescription)\n", stderr)
        return 1
    }

    return 0
}

exit(main())
