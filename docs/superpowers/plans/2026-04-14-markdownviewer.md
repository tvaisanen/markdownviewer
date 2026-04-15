# MarkdownViewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS AppKit app that renders markdown files with Mermaid and PlantUML diagram support — `open foo.md` just works.

**Architecture:** Xcode project (generated via xcodegen) with two targets: `MarkdownViewer` (AppKit app shell) and `MarkdownViewerKit` (framework with all rendering logic). The rendering pipeline pre-processes markdown to extract diagram blocks, converts remaining markdown to HTML via cmark, then injects diagram HTML (Mermaid `<div>`s for client-side rendering, PlantUML inline SVGs) into an HTML template loaded in WKWebView.

**Tech Stack:** Swift 6.3, AppKit, WKWebView, apple/swift-cmark (SPM), mermaid.min.js (bundled), plantuml CLI (external/optional), xcodegen

---

## File Map

```
MarkdownViewer/
├── project.yml                              # xcodegen project definition
├── Sources/
│   ├── MarkdownViewer/                      # App target
│   │   ├── AppDelegate.swift                # NSApplicationDelegate, file open, dark mode
│   │   ├── ViewerWindow.swift               # NSWindow subclass, tabbingMode
│   │   └── ViewerWindowController.swift     # Owns WebContentView + FileWatcher
│   └── MarkdownViewerKit/                   # Framework target
│       ├── DiagramProcessor.swift           # Extract diagram fences, placeholder replacement
│       ├── MermaidRenderer.swift            # Wrap mermaid source in <div class="mermaid">
│       ├── PlantUMLRenderer.swift           # Shell out to plantuml -tsvg -pipe
│       ├── MarkdownRenderer.swift           # Orchestrate full pipeline: MD → HTML
│       ├── FileWatcher.swift                # DispatchSource file watcher with debounce
│       └── WebContentView.swift             # WKWebView wrapper, template loading, scroll
├── Resources/
│   ├── template.html                        # HTML wrapper with JS/CSS includes
│   ├── style.css                            # Typography, code blocks, dark/light
│   └── mermaid.min.js                       # Bundled Mermaid (downloaded in setup)
├── Tests/
│   └── MarkdownViewerKitTests/
│       ├── DiagramProcessorTests.swift
│       ├── MermaidRendererTests.swift
│       ├── PlantUMLRendererTests.swift
│       └── MarkdownRendererTests.swift
└── Fixtures/
    ├── simple.md                            # Plain markdown (no diagrams)
    ├── mermaid.md                           # Markdown with mermaid block
    ├── plantuml.md                          # Markdown with plantuml block
    └── mixed.md                             # Markdown with both diagram types
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: directory structure for Sources, Tests, Resources, Fixtures

- [ ] **Step 1: Initialize git repo**

```bash
cd /Users/tvaisanen/projects/markdownviewer
git init
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p Sources/MarkdownViewer
mkdir -p Sources/MarkdownViewerKit
mkdir -p Tests/MarkdownViewerKitTests
mkdir -p Resources
mkdir -p Fixtures
```

- [ ] **Step 3: Create project.yml**

Create `project.yml`:

```yaml
name: MarkdownViewer
options:
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true
packages:
  swift-cmark:
    url: https://github.com/apple/swift-cmark
    from: 0.6.0
targets:
  MarkdownViewerKit:
    type: framework
    platform: macOS
    sources:
      - Sources/MarkdownViewerKit
    dependencies:
      - package: swift-cmark
        product: cmark
    settings:
      SWIFT_VERSION: "6.0"
  MarkdownViewer:
    type: application
    platform: macOS
    sources:
      - Sources/MarkdownViewer
    resources:
      - path: Resources
        buildPhase: resources
    dependencies:
      - target: MarkdownViewerKit
    settings:
      SWIFT_VERSION: "6.0"
      INFOPLIST_FILE: Sources/MarkdownViewer/Info.plist
    info:
      path: Sources/MarkdownViewer/Info.plist
      properties:
        CFBundleName: MarkdownViewer
        CFBundleDisplayName: MarkdownViewer
        CFBundleIdentifier: com.tvaisanen.markdownviewer
        CFBundleVersion: "1"
        CFBundleShortVersionString: "0.1.0"
        CFBundlePackageType: APPL
        CFBundleExecutable: MarkdownViewer
        NSPrincipalClass: NSApplication
        CFBundleDocumentTypes:
          - CFBundleTypeName: Markdown Document
            CFBundleTypeRole: Viewer
            LSItemContentTypes:
              - net.daringfireball.markdown
            LSHandlerRank: Default
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: net.daringfireball.markdown
            UTTypeDescription: Markdown Document
            UTTypeConformsTo:
              - public.plain-text
            UTTypeTagSpecification:
              public.filename-extension:
                - md
                - markdown
                - mdown
  MarkdownViewerKitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/MarkdownViewerKitTests
    dependencies:
      - target: MarkdownViewerKit
    settings:
      SWIFT_VERSION: "6.0"
```

- [ ] **Step 4: Create placeholder source files so xcodegen succeeds**

Create `Sources/MarkdownViewer/AppDelegate.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }
}
```

Create `Sources/MarkdownViewerKit/MarkdownRenderer.swift`:

```swift
import Foundation

public struct MarkdownRenderer {
}
```

Create `Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class MarkdownRendererTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Generate Xcode project**

```bash
cd /Users/tvaisanen/projects/markdownviewer
xcodegen generate
```

Expected: `Generated MarkdownViewer.xcodeproj`

- [ ] **Step 6: Verify it builds**

```bash
xcodebuild -project MarkdownViewer.xcodeproj -scheme MarkdownViewer -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Create .gitignore and commit**

Create `.gitignore`:

```
# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.moved-aside
*.xcuserstate

# macOS
.DS_Store

# Swift Package Manager
.build/
.swiftpm/
Packages/
```

```bash
git add -A
git commit -m "chore: scaffold Xcode project with xcodegen"
```

---

### Task 2: Resources — HTML Template, CSS, Mermaid.js

**Files:**
- Create: `Resources/template.html`
- Create: `Resources/style.css`
- Create: `Resources/mermaid.min.js` (downloaded)

- [ ] **Step 1: Create template.html**

Create `Resources/template.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="style.css">
    <script src="mermaid.min.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            mermaid.initialize({ startOnLoad: true, theme: 'default' });
        });

        function setMermaidTheme(theme) {
            mermaid.initialize({ startOnLoad: false, theme: theme });
            document.querySelectorAll('.mermaid').forEach(function(el) {
                var source = el.getAttribute('data-source');
                if (source) {
                    el.removeAttribute('data-processed');
                    el.innerHTML = source;
                }
            });
            mermaid.run();
        }
    </script>
</head>
<body>
{{CONTENT}}
</body>
</html>
```

- [ ] **Step 2: Create style.css**

Create `Resources/style.css`:

```css
:root {
    --text-color: #1a1a1a;
    --bg-color: #ffffff;
    --code-bg: #f5f5f5;
    --border-color: #e0e0e0;
    --link-color: #0366d6;
    --blockquote-color: #6a737d;
}

@media (prefers-color-scheme: dark) {
    :root {
        --text-color: #e0e0e0;
        --bg-color: #1a1a1a;
        --code-bg: #2d2d2d;
        --border-color: #404040;
        --link-color: #58a6ff;
        --blockquote-color: #8b949e;
    }
}

* {
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.6;
    color: var(--text-color);
    background-color: var(--bg-color);
    max-width: 900px;
    margin: 0 auto;
    padding: 20px 40px;
}

h1, h2, h3, h4, h5, h6 {
    margin-top: 1.5em;
    margin-bottom: 0.5em;
    font-weight: 600;
    line-height: 1.25;
}

h1 { font-size: 2em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
h2 { font-size: 1.5em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
h3 { font-size: 1.25em; }

a {
    color: var(--link-color);
    text-decoration: none;
}

a:hover {
    text-decoration: underline;
}

code {
    font-family: "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.875em;
    background-color: var(--code-bg);
    padding: 0.2em 0.4em;
    border-radius: 4px;
}

pre {
    background-color: var(--code-bg);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 16px;
    overflow-x: auto;
    line-height: 1.45;
}

pre code {
    background: none;
    padding: 0;
    border-radius: 0;
    font-size: 0.85em;
}

blockquote {
    color: var(--blockquote-color);
    border-left: 4px solid var(--border-color);
    padding: 0 1em;
    margin: 0;
}

table {
    border-collapse: collapse;
    width: 100%;
    margin: 1em 0;
}

th, td {
    border: 1px solid var(--border-color);
    padding: 8px 12px;
    text-align: left;
}

th {
    background-color: var(--code-bg);
    font-weight: 600;
}

img {
    max-width: 100%;
    height: auto;
}

hr {
    border: none;
    border-top: 1px solid var(--border-color);
    margin: 2em 0;
}

.mermaid {
    text-align: center;
    margin: 1em 0;
}

.plantuml-error, .plantuml-placeholder {
    background-color: var(--code-bg);
    border: 1px dashed var(--border-color);
    border-radius: 6px;
    padding: 20px;
    text-align: center;
    color: var(--blockquote-color);
    margin: 1em 0;
}
```

- [ ] **Step 3: Download mermaid.min.js**

```bash
curl -L -o /Users/tvaisanen/projects/markdownviewer/Resources/mermaid.min.js \
  "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
```

Verify the file is non-empty:

```bash
wc -c Resources/mermaid.min.js
```

Expected: file should be ~2-3 MB.

- [ ] **Step 4: Regenerate Xcode project and commit**

```bash
cd /Users/tvaisanen/projects/markdownviewer
xcodegen generate
git add Resources/
git commit -m "feat: add HTML template, CSS styles, and bundled mermaid.min.js"
```

---

### Task 3: Test Fixtures

**Files:**
- Create: `Fixtures/simple.md`
- Create: `Fixtures/mermaid.md`
- Create: `Fixtures/plantuml.md`
- Create: `Fixtures/mixed.md`

- [ ] **Step 1: Create simple.md**

Create `Fixtures/simple.md`:

```markdown
# Hello World

This is a **simple** markdown file with no diagrams.

- Item one
- Item two
- Item three

## Code Block

\`\`\`swift
let x = 42
print(x)
\`\`\`

> A blockquote for good measure.
```

- [ ] **Step 2: Create mermaid.md**

Create `Fixtures/mermaid.md`:

```markdown
# Mermaid Test

A flowchart:

\`\`\`mermaid
graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action]
    B -->|No| D[Other Action]
    C --> E[End]
    D --> E
\`\`\`

Some text after the diagram.
```

- [ ] **Step 3: Create plantuml.md**

Create `Fixtures/plantuml.md`:

```markdown
# PlantUML Test

A sequence diagram:

\`\`\`plantuml
@startuml
Alice -> Bob: Hello
Bob --> Alice: Hi there
@enduml
\`\`\`

Some text after the diagram.
```

- [ ] **Step 4: Create mixed.md**

Create `Fixtures/mixed.md`:

```markdown
# Mixed Diagrams

## Mermaid Flowchart

\`\`\`mermaid
graph LR
    A --> B --> C
\`\`\`

## PlantUML Sequence

\`\`\`plantuml
@startuml
User -> App: Request
App --> User: Response
@enduml
\`\`\`

## Regular Code

\`\`\`python
print("not a diagram")
\`\`\`

Done.
```

- [ ] **Step 5: Commit**

```bash
git add Fixtures/
git commit -m "feat: add test fixture markdown files"
```

---

### Task 4: DiagramProcessor — TDD

**Files:**
- Create: `Sources/MarkdownViewerKit/DiagramProcessor.swift`
- Create: `Tests/MarkdownViewerKitTests/DiagramProcessorTests.swift`

The DiagramProcessor scans raw markdown for ` ```mermaid ` and ` ```plantuml ` fenced code blocks, extracts them, replaces them with HTML comment placeholders, and later substitutes rendered diagram HTML back in.

- [ ] **Step 1: Write failing tests**

Create `Tests/MarkdownViewerKitTests/DiagramProcessorTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class DiagramProcessorTests: XCTestCase {

    func testNoDiagrams() {
        let markdown = "# Hello\n\nSome text.\n"
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.processedMarkdown, markdown)
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func testExtractMermaidBlock() {
        let markdown = """
        # Title

        ```mermaid
        graph TD
            A --> B
        ```

        After.
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].type, .mermaid)
        XCTAssertTrue(result.blocks[0].source.contains("graph TD"))
        XCTAssertTrue(result.processedMarkdown.contains("<!--DIAGRAM:"))
        XCTAssertFalse(result.processedMarkdown.contains("```mermaid"))
    }

    func testExtractPlantUMLBlock() {
        let markdown = """
        # Title

        ```plantuml
        @startuml
        Alice -> Bob: Hello
        @enduml
        ```

        After.
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].type, .plantuml)
        XCTAssertTrue(result.blocks[0].source.contains("Alice -> Bob"))
    }

    func testExtractMixedBlocks() {
        let markdown = """
        ```mermaid
        graph LR
            A --> B
        ```

        ```plantuml
        @startuml
        A -> B
        @enduml
        ```

        ```swift
        let x = 1
        ```
        """
        let result = DiagramProcessor.extractDiagrams(from: markdown)
        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.blocks[0].type, .mermaid)
        XCTAssertEqual(result.blocks[1].type, .plantuml)
        // Regular code blocks are untouched
        XCTAssertTrue(result.processedMarkdown.contains("```swift"))
    }

    func testInjectRenderedDiagrams() {
        let markdown = "```mermaid\ngraph TD\n    A --> B\n```\n"
        let extracted = DiagramProcessor.extractDiagrams(from: markdown)
        let rendered = [extracted.blocks[0].id: "<div class=\"mermaid\">graph TD\n    A --> B</div>"]
        let html = DiagramProcessor.injectDiagrams(into: extracted.processedMarkdown, renderedBlocks: rendered)
        XCTAssertTrue(html.contains("<div class=\"mermaid\">"))
        XCTAssertFalse(html.contains("<!--DIAGRAM:"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: compilation errors — `DiagramProcessor` does not exist.

- [ ] **Step 3: Implement DiagramProcessor**

Create `Sources/MarkdownViewerKit/DiagramProcessor.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: all 5 tests pass, `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewerKit/DiagramProcessor.swift Tests/MarkdownViewerKitTests/DiagramProcessorTests.swift
git commit -m "feat: add DiagramProcessor with fence extraction and placeholder injection"
```

---

### Task 5: MermaidRenderer — TDD

**Files:**
- Create: `Sources/MarkdownViewerKit/MermaidRenderer.swift`
- Create: `Tests/MarkdownViewerKitTests/MermaidRendererTests.swift`

MermaidRenderer wraps diagram source in a `<div class="mermaid">` with a `data-source` attribute (for re-rendering on theme change).

- [ ] **Step 1: Write failing tests**

Create `Tests/MarkdownViewerKitTests/MermaidRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class MermaidRendererTests: XCTestCase {

    func testRenderWrapsInDiv() {
        let source = "graph TD\n    A --> B"
        let html = MermaidRenderer.render(source: source)
        XCTAssertTrue(html.contains("<div class=\"mermaid\""))
        XCTAssertTrue(html.contains("graph TD"))
        XCTAssertTrue(html.contains("A --> B"))
        XCTAssertTrue(html.contains("</div>"))
    }

    func testRenderIncludesDataSource() {
        let source = "graph LR\n    X --> Y"
        let html = MermaidRenderer.render(source: source)
        XCTAssertTrue(html.contains("data-source="))
    }

    func testRenderEscapesHTMLInDataSource() {
        let source = "graph TD\n    A[\"<script>alert('xss')</script>\"] --> B"
        let html = MermaidRenderer.render(source: source)
        // data-source attribute must have HTML-escaped content
        XCTAssertFalse(html.contains("<script>alert"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: compilation errors — `MermaidRenderer` does not exist.

- [ ] **Step 3: Implement MermaidRenderer**

Create `Sources/MarkdownViewerKit/MermaidRenderer.swift`:

```swift
import Foundation

public enum MermaidRenderer {

    public static func render(source: String) -> String {
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <div class="mermaid" data-source="\(escapedSource)">
        \(source)
        </div>
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: all MermaidRenderer tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewerKit/MermaidRenderer.swift Tests/MarkdownViewerKitTests/MermaidRendererTests.swift
git commit -m "feat: add MermaidRenderer — wraps diagram source in div for client-side rendering"
```

---

### Task 6: PlantUMLRenderer — TDD

**Files:**
- Create: `Sources/MarkdownViewerKit/PlantUMLRenderer.swift`
- Create: `Tests/MarkdownViewerKitTests/PlantUMLRendererTests.swift`

PlantUMLRenderer shells out to `plantuml -tsvg -pipe`, returns inline SVG. Shows placeholder if binary not found, error on timeout.

- [ ] **Step 1: Write failing tests**

Create `Tests/MarkdownViewerKitTests/PlantUMLRendererTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: compilation errors — `PlantUMLRenderer` does not exist.

- [ ] **Step 3: Implement PlantUMLRenderer**

Create `Sources/MarkdownViewerKit/PlantUMLRenderer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: placeholder test passes, SVG test passes or skips if plantuml not installed.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewerKit/PlantUMLRenderer.swift Tests/MarkdownViewerKitTests/PlantUMLRendererTests.swift
git commit -m "feat: add PlantUMLRenderer — shells out to plantuml CLI with timeout and fallback"
```

---

### Task 7: MarkdownRenderer — TDD

**Files:**
- Create: `Sources/MarkdownViewerKit/MarkdownRenderer.swift` (replace placeholder)
- Create: `Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift` (replace placeholder)

MarkdownRenderer orchestrates the full pipeline: extract diagrams → render diagrams → convert markdown to HTML via cmark → inject diagrams → wrap in template.

- [ ] **Step 1: Write failing tests**

Replace `Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class MarkdownRendererTests: XCTestCase {

    func testPlainMarkdownToHTML() {
        let markdown = "# Hello\n\nThis is **bold** text.\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
    }

    func testMermaidBlockBecomesDiv() {
        let markdown = "# Test\n\n```mermaid\ngraph TD\n    A --> B\n```\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("<div class=\"mermaid\""))
        XCTAssertTrue(html.contains("graph TD"))
        XCTAssertFalse(html.contains("```mermaid"))
    }

    func testPlantUMLBlockShowsPlaceholderWhenNotInstalled() {
        let markdown = "```plantuml\n@startuml\nA -> B\n@enduml\n```\n"
        let renderer = MarkdownRenderer(plantUMLBinaryPath: "/nonexistent/plantuml")
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("plantuml-placeholder") || html.contains("<svg"),
                      "Expected either placeholder or SVG")
    }

    func testRegularCodeBlocksPreserved() {
        let markdown = "```swift\nlet x = 42\n```\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderBody(markdown: markdown)
        XCTAssertTrue(html.contains("let x = 42"))
        XCTAssertFalse(html.contains("mermaid"))
    }

    func testFullHTMLIncludesTemplate() {
        let markdown = "# Hello\n"
        let renderer = MarkdownRenderer()
        let html = renderer.renderFull(markdown: markdown, templateHTML: "<html><body>{{CONTENT}}</body></html>")
        XCTAssertTrue(html.contains("<html>"))
        XCTAssertTrue(html.contains("<h1>"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: compilation errors — `MarkdownRenderer` methods don't exist.

- [ ] **Step 3: Implement MarkdownRenderer**

Replace `Sources/MarkdownViewerKit/MarkdownRenderer.swift`:

```swift
import Foundation
import cmark

public final class MarkdownRenderer: Sendable {

    private let plantUMLRenderer: PlantUMLRenderer

    public init(plantUMLBinaryPath: String? = nil) {
        self.plantUMLRenderer = PlantUMLRenderer(binaryPath: plantUMLBinaryPath)
    }

    /// Renders markdown to an HTML body fragment (no <html>/<head> wrapper).
    public func renderBody(markdown: String) -> String {
        // 1. Extract diagram blocks, replace with placeholders
        let extraction = DiagramProcessor.extractDiagrams(from: markdown)

        // 2. Render each diagram block
        var renderedBlocks: [String: String] = [:]
        for block in extraction.blocks {
            switch block.type {
            case .mermaid:
                renderedBlocks[block.id] = MermaidRenderer.render(source: block.source)
            case .plantuml:
                renderedBlocks[block.id] = plantUMLRenderer.render(source: block.source)
            }
        }

        // 3. Convert remaining markdown to HTML via cmark
        let cmarkHTML = cmarkToHTML(extraction.processedMarkdown)

        // 4. Inject rendered diagrams back into HTML
        return DiagramProcessor.injectDiagrams(into: cmarkHTML, renderedBlocks: renderedBlocks)
    }

    /// Renders markdown into a full HTML document using the given template.
    /// The template must contain `{{CONTENT}}` as the placeholder.
    public func renderFull(markdown: String, templateHTML: String) -> String {
        let body = renderBody(markdown: markdown)
        return templateHTML.replacingOccurrences(of: "{{CONTENT}}", with: body)
    }

    private func cmarkToHTML(_ markdown: String) -> String {
        guard let cString = cmark_markdown_to_html(
            markdown,
            markdown.utf8.count,
            CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE
        ) else {
            return "<p>Failed to render markdown.</p>"
        }
        defer { free(cString) }
        return String(cString: cString)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: all MarkdownRenderer tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewerKit/MarkdownRenderer.swift Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift
git commit -m "feat: add MarkdownRenderer — full pipeline from markdown to HTML with diagram support"
```

---

### Task 8: FileWatcher

**Files:**
- Create: `Sources/MarkdownViewerKit/FileWatcher.swift`

FileWatcher uses DispatchSource to watch file changes with 200ms debounce.

- [ ] **Step 1: Implement FileWatcher**

Create `Sources/MarkdownViewerKit/FileWatcher.swift`:

```swift
import Foundation

public final class FileWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let debounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.tvaisanen.markdownviewer.filewatcher")

    public var onChange: (() -> Void)?

    public init(debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    public func watch(path: String) {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
    }

    private func handleEvent() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKit -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownViewerKit/FileWatcher.swift
git commit -m "feat: add FileWatcher — DispatchSource file monitoring with debounce"
```

---

### Task 9: WebContentView

**Files:**
- Create: `Sources/MarkdownViewerKit/WebContentView.swift`

WKWebView wrapper that loads rendered HTML with resource base URL and handles scroll position preservation.

- [ ] **Step 1: Implement WebContentView**

Create `Sources/MarkdownViewerKit/WebContentView.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKit -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownViewerKit/WebContentView.swift
git commit -m "feat: add WebContentView — WKWebView wrapper with scroll preservation"
```

---

### Task 10: ViewerWindow and ViewerWindowController

**Files:**
- Create: `Sources/MarkdownViewer/ViewerWindow.swift`
- Create: `Sources/MarkdownViewer/ViewerWindowController.swift`

- [ ] **Step 1: Implement ViewerWindow**

Create `Sources/MarkdownViewer/ViewerWindow.swift`:

```swift
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
```

- [ ] **Step 2: Implement ViewerWindowController**

Create `Sources/MarkdownViewer/ViewerWindowController.swift`:

```swift
import Cocoa
import MarkdownViewerKit

final class ViewerWindowController: NSWindowController {

    let fileURL: URL
    private let contentView = WebContentView(frame: .zero)
    private let fileWatcher = FileWatcher()
    private let renderer = MarkdownRenderer()
    private var templateHTML: String = ""
    private var isFirstLoad = true

    init(fileURL: URL) {
        self.fileURL = fileURL
        let window = ViewerWindow(for: fileURL)
        super.init(window: window)
        window.contentView = contentView
        loadTemplate()
        loadFile()
        startWatching()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func loadTemplate() {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "html"),
              let html = try? String(contentsOf: templateURL, encoding: .utf8) else {
            templateHTML = "<html><body>{{CONTENT}}</body></html>"
            return
        }
        templateHTML = html
    }

    private func loadFile() {
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let html = renderer.renderFull(markdown: markdown, templateHTML: templateHTML)
        let resourcesURL = Bundle.main.resourceURL

        if isFirstLoad {
            isFirstLoad = false
            contentView.loadInitialHTML(html, baseURL: resourcesURL)
        } else {
            contentView.loadHTML(html, baseURL: resourcesURL)
        }
    }

    private func startWatching() {
        fileWatcher.onChange = { [weak self] in
            self?.loadFile()
        }
        fileWatcher.watch(path: fileURL.path)
    }

    func updateMermaidTheme(isDark: Bool) {
        contentView.setMermaidTheme(isDark ? "dark" : "default")
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild build -project MarkdownViewer.xcodeproj -scheme MarkdownViewer -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Sources/MarkdownViewer/ViewerWindow.swift Sources/MarkdownViewer/ViewerWindowController.swift
git commit -m "feat: add ViewerWindow and ViewerWindowController — tabbed windows with live reload"
```

---

### Task 11: AppDelegate — App Bootstrap and File Handling

**Files:**
- Modify: `Sources/MarkdownViewer/AppDelegate.swift`

- [ ] **Step 1: Implement full AppDelegate**

Replace `Sources/MarkdownViewer/AppDelegate.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [URL: ViewerWindowController] = [:]
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearanceChanges()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ensure we receive openFiles calls
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        openFiles(urls: urls)
        application.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows — could show an open dialog
            showOpenPanel()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - File opening

    private func openFiles(urls: [URL]) {
        for url in urls {
            openFile(url: url)
        }
    }

    private func openFile(url: URL) {
        // Already open? Bring to front.
        if let existing = windowControllers[url] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ViewerWindowController(fileURL: url)

        // Tab into existing window if one exists
        if let existingWindow = windowControllers.values.first?.window,
           let newWindow = controller.window {
            existingWindow.addTabbedWindow(newWindow, ordered: .above)
        }

        controller.window?.makeKeyAndOrderFront(nil)
        windowControllers[url] = controller

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.windowControllers.removeAll { $0.value.window === window }
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            openFiles(urls: panel.urls)
        }
    }

    // MARK: - Dark mode

    private func observeAppearanceChanges() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            let isDark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self?.windowControllers.values.forEach { $0.updateMermaidTheme(isDark: isDark) }
        }
    }
}
```

- [ ] **Step 2: Build the app**

```bash
xcodebuild build -project MarkdownViewer.xcodeproj -scheme MarkdownViewer -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownViewer/AppDelegate.swift
git commit -m "feat: implement AppDelegate — file open handling, tabbing, dark mode observation"
```

---

### Task 12: Integration — Build, Run, and Smoke Test

**Files:** None (testing only)

- [ ] **Step 1: Run unit tests**

```bash
xcodebuild test -project MarkdownViewer.xcodeproj -scheme MarkdownViewerKitTests -destination 'platform=macOS' 2>&1 | grep -E "(Test Case|error:|\*\* TEST)"
```

Expected: all tests pass.

- [ ] **Step 2: Build the app**

```bash
xcodebuild build -project MarkdownViewer.xcodeproj -scheme MarkdownViewer -destination 'platform=macOS' -derivedDataPath build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Locate and run the built app with a test fixture**

```bash
APP_PATH=$(find build -name "MarkdownViewer.app" -type d | head -1)
echo "App at: $APP_PATH"
killall MarkdownViewer 2>/dev/null; open "$APP_PATH" --args "$(pwd)/Fixtures/mixed.md"
```

Expected: app opens with `mixed.md` rendered — markdown content visible, Mermaid diagram rendered, PlantUML shows either diagram (if installed) or placeholder.

- [ ] **Step 4: Test tabbing — open a second file**

```bash
open "$APP_PATH" --args "$(pwd)/Fixtures/simple.md"
```

Expected: `simple.md` opens as a new tab in the existing window.

- [ ] **Step 5: Test live reload — edit a fixture**

In a separate terminal, edit `Fixtures/simple.md` and add a line. The app window should update within ~200ms without needing to manually refresh.

- [ ] **Step 6: Test dark mode toggle**

Toggle System Preferences → Appearance between Light and Dark. Mermaid diagrams should re-render with the appropriate theme.

- [ ] **Step 7: Commit any fixes from smoke testing**

```bash
git add -A
git commit -m "fix: address issues found during integration smoke testing"
```

(Only if changes were needed.)
