# PDF Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WYSIWYG PDF export to MarkdownViewer with a live-updating preview window, smart section-aware pagination, and three document themes (applied to both screen and PDF).

**Architecture:** One shared `PDFExporter` class in `MarkdownViewerKit` generates PDFs by loading the app's normal HTML render into a hidden `WKWebView` plus a thin `pdf-overlay.css` that adds paged-media rules (`@page`, break-avoid on figures/code/tables, white background). A `PDFPreviewWindowController` in the app target displays the generated PDF via PDFKit and re-renders on file changes. Document themes (Technical / Apple Docs / GitHub) are swappable stylesheets that affect both the on-screen viewer and the exported PDF.

**Tech Stack:** Swift 6, macOS 14+, AppKit, WebKit (`WKWebView.createPDF`), PDFKit (`PDFView`, `PDFThumbnailView`), XCTest. Build via `xcodegen` + `xcodebuild` (see `justfile`).

**Reference spec:** `docs/superpowers/specs/2026-04-22-pdf-export-design.md`

---

## Codebase context (read before starting)

- Markdown → HTML is `MarkdownRenderer.renderFull(markdown:templateHTML:)` at `Sources/MarkdownViewerKit/MarkdownRenderer.swift`. The template is `Resources/template.html` which has `{{CONTENT}}` and pulls in `style.css` and `mermaid.min.js`.
- The on-screen WebView wrapper is `WebContentView` at `Sources/MarkdownViewerKit/WebContentView.swift`. It exposes `loadHTML`, `setMermaidTheme`, `setBrightness`.
- Resources (`Resources/*`) are bundled into the app target via `project.yml` (`type: group, buildPhase: resources`). Adding new CSS/HTML files under `Resources/` auto-bundles them after running `xcodegen generate`.
- Tests live under `Tests/MarkdownViewerKitTests/` and use XCTest. Fixtures are plain `.md` files under `Fixtures/` at repo root.
- Build locally with `just build` (generates the Xcode project and compiles); run tests with `just test`. See `justfile` for exact commands.
- Project regeneration is needed any time you add a new Swift file or Resource — always run `xcodegen generate` (or `just build`) after creating files before expecting them in the build.

---

## File structure

**New files in `Sources/MarkdownViewerKit/`:**

- `PDFExportOptions.swift` — value type carrying theme, paper size, orientation, chrome toggles
- `PDFTheme.swift` — enum `.technical / .appleDocs / .gitHub` + per-theme defaults
- `PDFExporter.swift` — core generation class (async → PDF `Data`)
- `DiagramRenderCoordinator.swift` — factored out, waits for Mermaid + PlantUML render completion

**New files in `Resources/`:**

- `pdf-overlay.css` — paged-media-only CSS (@page, break rules, white bg)
- `themes/github.css` — default theme, mirrors current `style.css`
- `themes/technical.css` — serif, arXiv-like
- `themes/appledocs.css` — SF Pro, airy
- `template.html` is modified to accept a `{{THEME_HREF}}` placeholder

**New files in `Sources/MarkdownViewer/`:**

- `PDFPreviewWindowController.swift` — preview window with thumbnails + PDFView + toolbar
- `ThemeManager.swift` — holds current theme, persists to UserDefaults, broadcasts changes

**Modified files:**

- `Sources/MarkdownViewerKit/MarkdownRenderer.swift` — add a `renderFull` overload that accepts extra `<link>` hrefs for overlays
- `Sources/MarkdownViewerKit/WebContentView.swift` — expose the page-loaded Bool for diagram coordinator reuse (see Task 5)
- `Sources/MarkdownViewer/AppDelegate.swift` — add `File → Export as PDF…`, `View → Theme` submenu, wire ⌘P
- `Sources/MarkdownViewer/ViewerWindowController.swift` — apply current theme, route ⌘P to preview window
- `Resources/template.html` — replace hard-coded `style.css` `<link>` with theme + overlay placeholders

**New files in `Tests/MarkdownViewerKitTests/`:**

- `PDFExporterTests.swift`
- `PDFExportOptionsTests.swift`
- `Fixtures/pdf/simple.md`, `heading-break.md`, `large-image.md`, `long-code.md`

---

## Task 1: `PDFExportOptions` value type

**Files:**
- Create: `Sources/MarkdownViewerKit/PDFExportOptions.swift`
- Test: `Tests/MarkdownViewerKitTests/PDFExportOptionsTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/MarkdownViewerKitTests/PDFExportOptionsTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class PDFExportOptionsTests: XCTestCase {

    func testDefaultOptionsUseGitHubTheme() {
        let opts = PDFExportOptions.defaults
        XCTAssertEqual(opts.theme, .gitHub)
        XCTAssertEqual(opts.orientation, .portrait)
        XCTAssertFalse(opts.startNewPageAtH1)
    }

    func testPaperSizeLetterDimensionsInPoints() {
        let size = PDFExportOptions.PaperSize.letter.pointSize
        // 8.5in x 11in at 72 dpi
        XCTAssertEqual(size.width, 612, accuracy: 0.5)
        XCTAssertEqual(size.height, 792, accuracy: 0.5)
    }

    func testPaperSizeA4DimensionsInPoints() {
        let size = PDFExportOptions.PaperSize.a4.pointSize
        // 210mm x 297mm at 72 dpi
        XCTAssertEqual(size.width, 595, accuracy: 1.0)
        XCTAssertEqual(size.height, 842, accuracy: 1.0)
    }

    func testOrientationLandscapeSwapsDimensions() {
        let portrait = PDFExportOptions.PaperSize.letter.pointSize(orientation: .portrait)
        let landscape = PDFExportOptions.PaperSize.letter.pointSize(orientation: .landscape)
        XCTAssertEqual(portrait.width, landscape.height, accuracy: 0.5)
        XCTAssertEqual(portrait.height, landscape.width, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test` (or `xcodebuild test -scheme MarkdownViewerKitTests`)
Expected: FAIL — `PDFExportOptions` undefined.

- [ ] **Step 3: Implement `PDFExportOptions`**

Create `Sources/MarkdownViewerKit/PDFExportOptions.swift`:

```swift
import Foundation
import CoreGraphics

public struct PDFExportOptions: Equatable, Sendable {

    public enum Orientation: String, Equatable, Sendable, CaseIterable {
        case portrait
        case landscape
    }

    public enum PaperSize: String, Equatable, Sendable, CaseIterable {
        case letter
        case a4

        /// Base portrait dimensions in PDF points (1pt = 1/72in).
        public var pointSize: CGSize {
            switch self {
            case .letter: return CGSize(width: 612, height: 792)   // 8.5 x 11 in
            case .a4:     return CGSize(width: 595, height: 842)   // 210 x 297 mm
            }
        }

        public func pointSize(orientation: Orientation) -> CGSize {
            let base = pointSize
            switch orientation {
            case .portrait:  return base
            case .landscape: return CGSize(width: base.height, height: base.width)
            }
        }
    }

    public var theme: PDFTheme
    public var paperSize: PaperSize
    public var orientation: Orientation
    public var startNewPageAtH1: Bool
    public var showHeader: Bool
    public var showFooter: Bool
    /// Running header text; nil = use theme default behavior.
    public var headerText: String?

    public init(
        theme: PDFTheme = .gitHub,
        paperSize: PaperSize = .letter,
        orientation: Orientation = .portrait,
        startNewPageAtH1: Bool = false,
        showHeader: Bool = true,
        showFooter: Bool = true,
        headerText: String? = nil
    ) {
        self.theme = theme
        self.paperSize = paperSize
        self.orientation = orientation
        self.startNewPageAtH1 = startNewPageAtH1
        self.showHeader = showHeader
        self.showFooter = showFooter
        self.headerText = headerText
    }

    public static let defaults = PDFExportOptions()
}
```

Note: this references `PDFTheme` which will be defined in Task 2. The test file will not compile until Task 2 lands — that's expected. We'll run the tests after Task 2.

- [ ] **Step 4: Also create `PDFTheme.swift` stub so Task 1 compiles alone**

Create `Sources/MarkdownViewerKit/PDFTheme.swift` (full content replaced in Task 2):

```swift
import Foundation

public enum PDFTheme: String, Equatable, Sendable, CaseIterable {
    case technical
    case appleDocs
    case gitHub
}
```

- [ ] **Step 5: Regenerate Xcode project and run tests**

Run: `xcodegen generate && just test`
Expected: PASS for all four `PDFExportOptionsTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MarkdownViewerKit/PDFExportOptions.swift \
        Sources/MarkdownViewerKit/PDFTheme.swift \
        Tests/MarkdownViewerKitTests/PDFExportOptionsTests.swift \
        project.yml
# project.yml only if xcodegen regenerated it
git commit -m "feat(pdf): add PDFExportOptions value type with paper sizes and orientations"
```

---

## Task 2: Flesh out `PDFTheme` with per-theme metadata

**Files:**
- Modify: `Sources/MarkdownViewerKit/PDFTheme.swift`
- Test: `Tests/MarkdownViewerKitTests/PDFThemeTests.swift` (new)

- [ ] **Step 1: Write failing test**

Create `Tests/MarkdownViewerKitTests/PDFThemeTests.swift`:

```swift
import XCTest
@testable import MarkdownViewerKit

final class PDFThemeTests: XCTestCase {

    func testEachThemeHasUniqueStylesheetName() {
        let names = Set(PDFTheme.allCases.map(\.stylesheetFilename))
        XCTAssertEqual(names.count, PDFTheme.allCases.count)
    }

    func testStylesheetFilenamesMatchResources() {
        XCTAssertEqual(PDFTheme.gitHub.stylesheetFilename,    "github.css")
        XCTAssertEqual(PDFTheme.technical.stylesheetFilename, "technical.css")
        XCTAssertEqual(PDFTheme.appleDocs.stylesheetFilename, "appledocs.css")
    }

    func testDisplayNameIsHumanReadable() {
        XCTAssertEqual(PDFTheme.gitHub.displayName,    "GitHub")
        XCTAssertEqual(PDFTheme.technical.displayName, "Technical Paper")
        XCTAssertEqual(PDFTheme.appleDocs.displayName, "Apple Documentation")
    }

    func testDefaultChromeDiffersByTheme() {
        // Spec: technical → header+footer, appleDocs → footer only, github → none
        XCTAssertTrue(PDFTheme.technical.defaultShowHeader)
        XCTAssertTrue(PDFTheme.technical.defaultShowFooter)

        XCTAssertFalse(PDFTheme.appleDocs.defaultShowHeader)
        XCTAssertTrue(PDFTheme.appleDocs.defaultShowFooter)

        XCTAssertFalse(PDFTheme.gitHub.defaultShowHeader)
        XCTAssertFalse(PDFTheme.gitHub.defaultShowFooter)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL — `stylesheetFilename`, `displayName`, `defaultShowHeader`, `defaultShowFooter` not defined.

- [ ] **Step 3: Replace `PDFTheme.swift` with full implementation**

Overwrite `Sources/MarkdownViewerKit/PDFTheme.swift`:

```swift
import Foundation

public enum PDFTheme: String, Equatable, Sendable, CaseIterable {
    case technical
    case appleDocs
    case gitHub

    public var displayName: String {
        switch self {
        case .technical: return "Technical Paper"
        case .appleDocs: return "Apple Documentation"
        case .gitHub:    return "GitHub"
        }
    }

    /// Filename inside `Resources/themes/`.
    public var stylesheetFilename: String {
        switch self {
        case .technical: return "technical.css"
        case .appleDocs: return "appledocs.css"
        case .gitHub:    return "github.css"
        }
    }

    public var defaultShowHeader: Bool {
        switch self {
        case .technical: return true
        case .appleDocs: return false
        case .gitHub:    return false
        }
    }

    public var defaultShowFooter: Bool {
        switch self {
        case .technical: return true
        case .appleDocs: return true
        case .gitHub:    return false
        }
    }
}
```

- [ ] **Step 4: Run test**

Run: `just test`
Expected: PASS for `PDFThemeTests` (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewerKit/PDFTheme.swift \
        Tests/MarkdownViewerKitTests/PDFThemeTests.swift
git commit -m "feat(pdf): PDFTheme metadata — display names and chrome defaults"
```

---

## Task 3: Create theme stylesheets (resources)

**Files:**
- Create: `Resources/themes/github.css`
- Create: `Resources/themes/technical.css`
- Create: `Resources/themes/appledocs.css`

These are the *full content* stylesheets applied to both screen and PDF. Start by mirroring the current `Resources/style.css` into `github.css` so the default user-visible behavior doesn't change. Then write the other two.

- [ ] **Step 1: Copy current `style.css` to `Resources/themes/github.css`**

Copy the full contents of `Resources/style.css` to `Resources/themes/github.css` verbatim. (No changes — it is already the "GitHub-ish" look.)

- [ ] **Step 2: Write `Resources/themes/technical.css`**

Create `Resources/themes/technical.css`:

```css
:root {
    --text-color: #111111;
    --bg-color: #ffffff;
    --code-bg: #f4f1ea;
    --border-color: #d6d3cc;
    --link-color: #b1361e;
    --blockquote-color: #555555;
}

@media (prefers-color-scheme: dark) {
    :root {
        --text-color: #e8e4da;
        --bg-color: #1c1a17;
        --code-bg: #2a2622;
        --border-color: #3a342d;
        --link-color: #e0845f;
        --blockquote-color: #a8a298;
    }
}

* { box-sizing: border-box; }

body {
    font-family: "Charter", "Iowan Old Style", Palatino, Georgia, serif;
    font-size: 17px;
    line-height: 1.55;
    color: var(--text-color);
    background-color: var(--bg-color);
    max-width: 720px;
    margin: 0 auto;
    padding: 24px 48px;
}

h1, h2, h3, h4, h5, h6 {
    font-family: "Charter", "Iowan Old Style", Palatino, Georgia, serif;
    font-weight: 700;
    margin-top: 1.6em;
    margin-bottom: 0.5em;
    line-height: 1.2;
}

h1 { font-size: 2.2em; }
h2 { font-size: 1.6em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.2em; }
h3 { font-size: 1.3em; }

p, li { hyphens: auto; }

a { color: var(--link-color); text-decoration: none; }
a:hover { text-decoration: underline; }

code {
    font-family: "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.88em;
    background-color: var(--code-bg);
    padding: 0.15em 0.35em;
    border-radius: 3px;
}

pre {
    background-color: var(--code-bg);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    padding: 14px;
    overflow-x: auto;
    line-height: 1.45;
    font-size: 0.88em;
}

pre code { background: none; padding: 0; }

blockquote {
    color: var(--blockquote-color);
    border-left: 3px solid var(--border-color);
    padding: 0 1em;
    margin: 1em 0;
    font-style: italic;
}

table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 0.95em; }
th, td { border: 1px solid var(--border-color); padding: 6px 10px; text-align: left; }
th { background-color: var(--code-bg); font-weight: 700; }

img { max-width: 100%; height: auto; }
hr { border: none; border-top: 1px solid var(--border-color); margin: 2em 0; }

.mermaid { text-align: center; margin: 1em 0; }
.plantuml-error, .plantuml-placeholder {
    background-color: var(--code-bg);
    border: 1px dashed var(--border-color);
    border-radius: 4px;
    padding: 20px;
    text-align: center;
    color: var(--blockquote-color);
    margin: 1em 0;
}
```

- [ ] **Step 3: Write `Resources/themes/appledocs.css`**

Create `Resources/themes/appledocs.css`:

```css
:root {
    --text-color: #1d1d1f;
    --bg-color: #ffffff;
    --code-bg: #f5f5f7;
    --border-color: #d2d2d7;
    --link-color: #0066cc;
    --blockquote-color: #6e6e73;
}

@media (prefers-color-scheme: dark) {
    :root {
        --text-color: #f5f5f7;
        --bg-color: #1d1d1f;
        --code-bg: #2c2c2e;
        --border-color: #3a3a3c;
        --link-color: #4493f8;
        --blockquote-color: #8e8e93;
    }
}

* { box-sizing: border-box; }

body {
    font-family: -apple-system, "SF Pro Text", BlinkMacSystemFont, sans-serif;
    font-size: 16px;
    line-height: 1.65;
    color: var(--text-color);
    background-color: var(--bg-color);
    max-width: 820px;
    margin: 0 auto;
    padding: 32px 56px;
    -webkit-font-smoothing: antialiased;
}

h1, h2, h3, h4, h5, h6 {
    font-family: -apple-system, "SF Pro Display", BlinkMacSystemFont, sans-serif;
    font-weight: 700;
    letter-spacing: -0.015em;
    margin-top: 1.8em;
    margin-bottom: 0.4em;
    line-height: 1.18;
}

h1 { font-size: 2.4em; font-weight: 800; letter-spacing: -0.02em; }
h2 { font-size: 1.7em; }
h3 { font-size: 1.3em; }

a { color: var(--link-color); text-decoration: none; }
a:hover { text-decoration: underline; }

code {
    font-family: "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.9em;
    background-color: var(--code-bg);
    padding: 0.15em 0.4em;
    border-radius: 4px;
}

pre {
    background-color: var(--code-bg);
    border: none;
    border-radius: 8px;
    padding: 18px;
    overflow-x: auto;
    line-height: 1.5;
}
pre code { background: none; padding: 0; font-size: 0.88em; }

blockquote {
    color: var(--blockquote-color);
    border-left: 3px solid var(--link-color);
    padding: 0 1em;
    margin: 1.2em 0;
}

table { border-collapse: collapse; width: 100%; margin: 1.2em 0; }
th, td {
    border-bottom: 1px solid var(--border-color);
    padding: 10px 14px;
    text-align: left;
}
th { font-weight: 600; color: var(--blockquote-color); font-size: 0.9em; text-transform: uppercase; letter-spacing: 0.05em; }

img { max-width: 100%; height: auto; border-radius: 8px; }
hr { border: none; border-top: 1px solid var(--border-color); margin: 2.5em 0; }

.mermaid { text-align: center; margin: 1.5em 0; }
.plantuml-error, .plantuml-placeholder {
    background-color: var(--code-bg);
    border: none;
    border-radius: 8px;
    padding: 24px;
    text-align: center;
    color: var(--blockquote-color);
    margin: 1.5em 0;
}
```

- [ ] **Step 4: Regenerate project so Resources pick up new files**

Run: `xcodegen generate && just build`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Resources/themes/
git commit -m "feat(pdf): add three document themes (GitHub, Technical Paper, Apple Docs)"
```

---

## Task 4: Create `pdf-overlay.css` (paged-media-only rules)

**Files:**
- Create: `Resources/pdf-overlay.css`

This is the thin overlay appended ONLY during PDF generation. It adds page breaks and sets a white background; it does NOT restyle content (that's the theme's job).

- [ ] **Step 1: Write `Resources/pdf-overlay.css`**

Create `Resources/pdf-overlay.css`:

```css
/* PDF overlay — applied in addition to the active theme during PDF export. */

@page {
    /* margins set dynamically via injected @page rule */
    margin: 0.75in;
}

html, body {
    background: #ffffff !important;
    filter: none !important;   /* disable the brightness slider for print */
}

/* Keep headings with their following content */
h1, h2, h3, h4, h5, h6 {
    break-after: avoid-page;
    page-break-after: avoid;
}

/* Never split figures, diagrams, or images */
img, svg, figure, .mermaid, .plantuml-placeholder, .plantuml-error {
    break-inside: avoid-page;
    page-break-inside: avoid;
    max-width: 100%;
    max-height: 95vh;
    height: auto;
}

/* Tables try not to split header rows from body */
table { break-inside: auto; }
thead { display: table-header-group; }
tr    { break-inside: avoid-page; page-break-inside: avoid; }

/* Code blocks: avoid splits when short, allow when they exceed a page */
pre {
    break-inside: auto;
    page-break-inside: auto;
    white-space: pre-wrap;   /* wrap long lines instead of horizontal scroll */
    word-wrap: break-word;
}

/* Opt-in: start a new page at each H1 */
body.pdf-start-h1-new-page > h1,
body.pdf-start-h1-new-page h1:not(:first-of-type) {
    break-before: page;
    page-break-before: always;
}

/* Hide anything marked as screen-only */
.screen-only { display: none !important; }
```

- [ ] **Step 2: Regenerate project**

Run: `xcodegen generate && just build`

- [ ] **Step 3: Commit**

```bash
git add Resources/pdf-overlay.css
git commit -m "feat(pdf): paged-media overlay CSS (break rules, white bg)"
```

---

## Task 5: Modify `template.html` and `MarkdownRenderer` to accept theme + overlay

The template currently hard-codes `<link rel="stylesheet" href="style.css">`. Replace with placeholders for the theme stylesheet and optional overlay list.

**Files:**
- Modify: `Resources/template.html`
- Modify: `Sources/MarkdownViewerKit/MarkdownRenderer.swift`
- Test: `Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift`

- [ ] **Step 1: Add failing tests for the new `renderFull` overload**

Append to `Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift`:

```swift
    func testRenderFullAppliesTheme() {
        let template = """
        <html><head>{{EXTRA_HEAD}}</head><body>{{CONTENT}}</body></html>
        """
        let renderer = MarkdownRenderer()
        let html = renderer.renderFull(
            markdown: "# Hi",
            templateHTML: template,
            extraStylesheetHrefs: ["themes/technical.css", "pdf-overlay.css"],
            bodyClasses: ["pdf-start-h1-new-page"]
        )
        XCTAssertTrue(html.contains("themes/technical.css"))
        XCTAssertTrue(html.contains("pdf-overlay.css"))
        XCTAssertTrue(html.contains("<body class=\"pdf-start-h1-new-page\">"))
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL — overload doesn't exist.

- [ ] **Step 3: Modify `Resources/template.html`**

Replace entire contents of `Resources/template.html` with:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    {{EXTRA_HEAD}}
    <script src="mermaid.min.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            mermaid.initialize({ startOnLoad: true, theme: 'neutral' });
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
<body{{BODY_ATTRS}}>
{{CONTENT}}
</body>
</html>
```

Note: the `style.css` link is gone. Every call site must now supply the theme stylesheet via `extraStylesheetHrefs`.

- [ ] **Step 4: Extend `MarkdownRenderer.renderFull`**

Modify `Sources/MarkdownViewerKit/MarkdownRenderer.swift`. Keep the existing 2-argument `renderFull` working (it can insert nothing into the placeholders so legacy templates still render). Add a 4-argument overload:

```swift
    /// Renders full HTML with optional extra stylesheets injected into the head
    /// and optional CSS classes applied to `<body>`.
    ///
    /// Template placeholders: `{{EXTRA_HEAD}}`, `{{BODY_ATTRS}}`, `{{CONTENT}}`.
    public func renderFull(
        markdown: String,
        templateHTML: String,
        extraStylesheetHrefs: [String],
        bodyClasses: [String] = []
    ) -> String {
        let body = renderBody(markdown: markdown)

        let linkTags = extraStylesheetHrefs
            .map { "<link rel=\"stylesheet\" href=\"\($0)\">" }
            .joined(separator: "\n    ")

        let bodyAttrs: String = bodyClasses.isEmpty
            ? ""
            : " class=\"\(bodyClasses.joined(separator: " "))\""

        return templateHTML
            .replacingOccurrences(of: "{{EXTRA_HEAD}}", with: linkTags)
            .replacingOccurrences(of: "{{BODY_ATTRS}}", with: bodyAttrs)
            .replacingOccurrences(of: "{{CONTENT}}", with: body)
    }
```

Also update the existing 2-argument `renderFull` to gracefully handle the new placeholders in templates that now include them:

```swift
    public func renderFull(markdown: String, templateHTML: String) -> String {
        let body = renderBody(markdown: markdown)
        return templateHTML
            .replacingOccurrences(of: "{{EXTRA_HEAD}}", with: "")
            .replacingOccurrences(of: "{{BODY_ATTRS}}", with: "")
            .replacingOccurrences(of: "{{CONTENT}}", with: body)
    }
```

- [ ] **Step 5: Run tests**

Run: `just test`
Expected: `testRenderFullAppliesTheme` PASS. Existing `testFullHTMLIncludesTemplate` still PASS.

- [ ] **Step 6: Update the viewer to pass the current theme into `renderFull`**

Temporary wiring so the app still renders after removing the auto-`style.css` link. Modify `Sources/MarkdownViewer/ViewerWindowController.swift` `renderSelectedFile()`:

Find:

```swift
        let html = renderer.renderFull(markdown: markdown, templateHTML: templateHTML)
```

Replace with:

```swift
        let html = renderer.renderFull(
            markdown: markdown,
            templateHTML: templateHTML,
            extraStylesheetHrefs: ["themes/github.css"]
        )
```

(This hardcodes the GitHub theme until Task 8 adds a real theme manager. That's intentional — we want each task shippable.)

- [ ] **Step 7: Delete the legacy `Resources/style.css`**

The three theme stylesheets replace it. Any reference to it would now break.

Run: `git rm Resources/style.css && xcodegen generate && just build`
Expected: build succeeds, viewer still renders (now using `github.css`).

- [ ] **Step 8: Manual smoke check**

Run: `just run Fixtures/simple.md`
Expected: content renders with same GitHub-like styling as before.

- [ ] **Step 9: Commit**

```bash
git add Sources/MarkdownViewerKit/MarkdownRenderer.swift \
        Sources/MarkdownViewer/ViewerWindowController.swift \
        Tests/MarkdownViewerKitTests/MarkdownRendererTests.swift \
        Resources/template.html
git add -u Resources/style.css      # deletion
git commit -m "refactor: template.html supports theme + overlay injection, drop style.css"
```

---

## Task 6: `DiagramRenderCoordinator` — wait for Mermaid / PlantUML completion

PDF generation must not start until Mermaid has rendered its SVGs. Mermaid renders asynchronously after `DOMContentLoaded`. PlantUML is server-side in the renderer, so it's already baked into the HTML before the WebView ever sees it — only Mermaid needs waiting.

**Files:**
- Create: `Sources/MarkdownViewerKit/DiagramRenderCoordinator.swift`

- [ ] **Step 1: Implement `DiagramRenderCoordinator`**

Create `Sources/MarkdownViewerKit/DiagramRenderCoordinator.swift`:

```swift
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
```

- [ ] **Step 2: Regenerate project**

Run: `xcodegen generate && just build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownViewerKit/DiagramRenderCoordinator.swift
git commit -m "feat(pdf): DiagramRenderCoordinator awaits Mermaid rendering"
```

No unit test here — the coordinator requires a live WKWebView and is covered end-to-end by the `PDFExporter` tests in Task 7.

---

## Task 7: `PDFExporter` — core generation

**Files:**
- Create: `Sources/MarkdownViewerKit/PDFExporter.swift`
- Test: `Tests/MarkdownViewerKitTests/PDFExporterTests.swift`
- Create fixtures: `Tests/MarkdownViewerKitTests/Fixtures/pdf/simple.md`, etc.

- [ ] **Step 1: Create test fixtures**

Create `Tests/MarkdownViewerKitTests/Fixtures/pdf/simple.md`:

```markdown
# Simple Document

This is a short paragraph used to verify single-page PDF generation.
```

Create `Tests/MarkdownViewerKitTests/Fixtures/pdf/heading-break.md`:

```markdown
# First Section

Some content in the first section.

# Second Section

Some content in the second section.
```

Create `Tests/MarkdownViewerKitTests/Fixtures/pdf/long-code.md`:

```markdown
# Long Code

```swift
// A very long code block designed to force a page split.
```
```

(Use 400+ lines of dummy code inside the fence — duplicate a simple `let x = \(i)` line. Generate the fixture via a script if needed; the test only cares it exceeds a page.)

Helper: create once with

```bash
cat > Tests/MarkdownViewerKitTests/Fixtures/pdf/long-code.md <<'EOF'
# Long Code

```swift
EOF
for i in $(seq 1 500); do echo "let x$i = $i" >> Tests/MarkdownViewerKitTests/Fixtures/pdf/long-code.md; done
cat >> Tests/MarkdownViewerKitTests/Fixtures/pdf/long-code.md <<'EOF'
```
EOF
```

- [ ] **Step 2: Register fixture folder in the test target**

Add to `project.yml` under `MarkdownViewerKitTests`. The test bundle needs both the fixtures AND the app's `Resources/` (template.html, themes/, pdf-overlay.css) so `PDFExporter` can find them when resolved via `Bundle(for: Self.self)`:

```yaml
  MarkdownViewerKitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/MarkdownViewerKitTests
      - path: Tests/MarkdownViewerKitTests/Fixtures
        type: group
        buildPhase: resources
      - path: Resources
        type: group
        buildPhase: resources
    dependencies:
      - target: MarkdownViewerKit
    settings:
      SWIFT_VERSION: "6.0"
```

Run: `xcodegen generate`
Expected: project regenerates without error.

- [ ] **Step 3: Write failing tests**

Create `Tests/MarkdownViewerKitTests/PDFExporterTests.swift`:

```swift
import XCTest
import PDFKit
@testable import MarkdownViewerKit

@MainActor
final class PDFExporterTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "Fixtures/pdf") else {
            throw XCTSkip("Missing fixture: \(name).md")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSimpleDocumentProducesOnePage() async throws {
        let markdown = try loadFixture("simple")
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: .defaults,
            documentTitle: "simple"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 1)
    }

    func testStartNewPageAtH1ProducesTwoPages() async throws {
        let markdown = try loadFixture("heading-break")
        var opts = PDFExportOptions.defaults
        opts.startNewPageAtH1 = true
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: opts,
            documentTitle: "heading-break"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 2)
    }

    func testLongCodeBlockIsAllowedToSplit() async throws {
        let markdown = try loadFixture("long-code")
        let exporter = PDFExporter(bundle: Bundle(for: Self.self))
        let data = try await exporter.exportPDF(
            markdown: markdown,
            options: .defaults,
            documentTitle: "long-code"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1)
    }

    func testEachThemeProducesNonEmptyPDF() async throws {
        let markdown = try loadFixture("simple")
        for theme in PDFTheme.allCases {
            var opts = PDFExportOptions.defaults
            opts.theme = theme
            let exporter = PDFExporter()
            let data = try await exporter.exportPDF(
                markdown: markdown,
                options: opts,
                documentTitle: "simple"
            )
            XCTAssertGreaterThan(data.count, 0, "\(theme) produced empty PDF")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `PDFExporter` undefined.

- [ ] **Step 5: Implement `PDFExporter`**

Create `Sources/MarkdownViewerKit/PDFExporter.swift`:

```swift
import Foundation
import WebKit

public enum PDFExportError: Error {
    case templateUnavailable
    case createPDFFailed(Error)
}

@MainActor
public final class PDFExporter {

    private let renderer: MarkdownRenderer
    private let bundle: Bundle

    public init(renderer: MarkdownRenderer = MarkdownRenderer(), bundle: Bundle = .main) {
        self.renderer = renderer
        self.bundle = bundle
    }

    /// Generate a PDF from the given markdown under the supplied options.
    /// `documentTitle` is used for the running header when enabled.
    public func exportPDF(
        markdown: String,
        options: PDFExportOptions,
        documentTitle: String
    ) async throws -> Data {
        let templateHTML = try loadTemplate()
        let extraStylesheets = [
            "themes/\(options.theme.stylesheetFilename)",
            "pdf-overlay.css"
        ]
        var bodyClasses: [String] = []
        if options.startNewPageAtH1 { bodyClasses.append("pdf-start-h1-new-page") }

        let injectedPageCSS = makePageCSS(options: options, title: documentTitle)
        let html = renderer.renderFull(
            markdown: markdown,
            templateHTML: injectPageCSS(into: templateHTML, css: injectedPageCSS),
            extraStylesheetHrefs: extraStylesheets,
            bodyClasses: bodyClasses
        )

        let pageSize = options.paperSize.pointSize(orientation: options.orientation)
        let webView = makeOffscreenWebView(pageSize: pageSize)

        let baseURL = bundle.resourceURL
        try await loadHTML(html: html, baseURL: baseURL, in: webView)

        _ = await DiagramRenderCoordinator.waitForDiagrams(in: webView)

        return try await createPDF(from: webView)
    }

    // MARK: - Private

    private func loadTemplate() throws -> String {
        guard
            let url = bundle.url(forResource: "template", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw PDFExportError.templateUnavailable
        }
        return html
    }

    /// Insert a page-media `<style>` block right after `{{EXTRA_HEAD}}`.
    private func injectPageCSS(into template: String, css: String) -> String {
        let styleTag = "<style>\n\(css)\n</style>"
        return template.replacingOccurrences(
            of: "{{EXTRA_HEAD}}",
            with: "{{EXTRA_HEAD}}\n    \(styleTag)"
        )
    }

    private func makePageCSS(options: PDFExportOptions, title: String) -> String {
        let size = options.paperSize.pointSize(orientation: options.orientation)
        let widthIn = size.width / 72.0
        let heightIn = size.height / 72.0

        let headerRule: String = options.showHeader
            ? "@top-right { content: \"\(escapeCSS(options.headerText ?? title))\"; font-size: 9pt; color: #888; }"
            : ""
        let footerRule: String = options.showFooter
            ? "@bottom-center { content: counter(page); font-size: 9pt; color: #888; }"
            : ""

        return """
        @page {
            size: \(widthIn)in \(heightIn)in;
            margin: 0.75in;
            \(headerRule)
            \(footerRule)
        }
        """
    }

    private func escapeCSS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func makeOffscreenWebView(pageSize: CGSize) -> WKWebView {
        let config = WKWebViewConfiguration()
        return WKWebView(
            frame: CGRect(origin: .zero, size: pageSize),
            configuration: config
        )
    }

    private func loadHTML(html: String, baseURL: URL?, in webView: WKWebView) async throws {
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        // Retain delegate until load completes — it's captured in the continuation closure above;
        // reassign after to release.
        webView.navigationDelegate = nil
    }

    private func createPDF(from webView: WKWebView) async throws -> Data {
        let config = WKPDFConfiguration()
        // Nil rect => capture entire scrollable content.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let err):  continuation.resume(throwing: PDFExportError.createPDFFailed(err))
                }
            }
        }
    }
}

@MainActor
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinish?()
    }
}
```

- [ ] **Step 6: Run tests**

Run: `just test`
Expected: the four `PDFExporterTests` PASS.

If `testSimpleDocumentProducesOnePage` produces more than 1 page, inspect: the `@page` size probably isn't being respected because `WKPDFConfiguration` with a nil rect uses the web view's content size rather than CSS page size. If that's the case:

- Adjust by setting `webView.frame = CGRect(origin: .zero, size: pageSize)` BEFORE calling `createPDF`, and pass a `rect` to `WKPDFConfiguration` equal to one page's bounds. Loop through the scroll height to capture multiple pages and merge with `PDFDocument.insert(_:at:)`.

Concretely: if the single-config call does not paginate correctly, replace `createPDF(from:)` with:

```swift
    private func createPDF(from webView: WKWebView, pageSize: CGSize) async throws -> Data {
        // Measure content height
        let rawHeight = await withCheckedContinuation { (c: CheckedContinuation<CGFloat, Never>) in
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                c.resume(returning: (result as? CGFloat) ?? pageSize.height)
            }
        }
        let totalHeight = max(rawHeight, pageSize.height)
        let pageCount = Int(ceil(totalHeight / pageSize.height))

        let combined = PDFDocument()
        for pageIndex in 0..<pageCount {
            let y = CGFloat(pageIndex) * pageSize.height
            let rect = CGRect(x: 0, y: y, width: pageSize.width, height: pageSize.height)
            let config = WKPDFConfiguration()
            config.rect = rect
            let data: Data = try await withCheckedThrowingContinuation { c in
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let d): c.resume(returning: d)
                    case .failure(let e): c.resume(throwing: PDFExportError.createPDFFailed(e))
                    }
                }
            }
            if let page = PDFDocument(data: data)?.page(at: 0) {
                combined.insert(page, at: combined.pageCount)
            }
        }

        return combined.dataRepresentation() ?? Data()
    }
```

Pass `pageSize: options.paperSize.pointSize(orientation: options.orientation)` through from `exportPDF`. `import PDFKit` at the top of the file.

- [ ] **Step 7: Commit**

```bash
git add Sources/MarkdownViewerKit/PDFExporter.swift \
        Tests/MarkdownViewerKitTests/PDFExporterTests.swift \
        Tests/MarkdownViewerKitTests/Fixtures/pdf/ \
        project.yml
git commit -m "feat(pdf): PDFExporter — WYSIWYG PDF generation with paged media"
```

---

## Task 8: `ThemeManager` — persist and broadcast document theme

**Files:**
- Create: `Sources/MarkdownViewer/ThemeManager.swift`
- Modify: `Sources/MarkdownViewer/ViewerWindowController.swift`

- [ ] **Step 1: Implement `ThemeManager`**

Create `Sources/MarkdownViewer/ThemeManager.swift`:

```swift
import Foundation
import MarkdownViewerKit

@MainActor
final class ThemeManager {

    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")
    private static let defaultsKey = "DocumentTheme"

    private init() {}

    var current: PDFTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
               let theme = PDFTheme(rawValue: raw) {
                return theme
            }
            return .gitHub
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: newValue)
        }
    }
}
```

- [ ] **Step 2: Wire `ViewerWindowController` to use `ThemeManager`**

In `Sources/MarkdownViewer/ViewerWindowController.swift`:

1. Replace the hardcoded `"themes/github.css"` in `renderSelectedFile()` with:

```swift
        let themeHref = "themes/\(ThemeManager.shared.current.stylesheetFilename)"
        let html = renderer.renderFull(
            markdown: markdown,
            templateHTML: templateHTML,
            extraStylesheetHrefs: [themeHref]
        )
```

2. In `init()`, after `loadTemplate()`, subscribe:

```swift
        NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.renderSelectedFile()
            }
        }
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && just build`
Expected: build succeeds.

- [ ] **Step 4: Smoke test**

Run: `just run Fixtures/simple.md`. In the LLDB console or a scratch:

```swift
// from Xcode breakpoint, or temporarily wire a menu action
ThemeManager.shared.current = .technical
```

Expected: viewer re-renders with serif typography.

Reset: `ThemeManager.shared.current = .gitHub`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewer/ThemeManager.swift \
        Sources/MarkdownViewer/ViewerWindowController.swift
git commit -m "feat: ThemeManager persists and broadcasts document theme"
```

---

## Task 9: `View → Theme` submenu

**Files:**
- Modify: `Sources/MarkdownViewer/AppDelegate.swift`

- [ ] **Step 1: Inspect `AppDelegate.swift` to find menu construction**

Run:

```bash
grep -n "NSMenu\|applicationDidFinishLaunching\|buildMainMenu\|viewMenu" \
    Sources/MarkdownViewer/AppDelegate.swift
```

Pick the method where the View menu is built.

- [ ] **Step 2: Add the `Theme` submenu**

Inside the View menu construction, add:

```swift
        let themeMenu = NSMenu(title: "Theme")
        for theme in PDFTheme.allCases {
            let item = NSMenuItem(
                title: theme.displayName,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            themeMenu.addItem(item)
        }
        let themeContainer = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeContainer.submenu = themeMenu
        viewMenu.addItem(themeContainer)
```

Add the action method on `AppDelegate`:

```swift
    @objc func selectTheme(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let theme = PDFTheme(rawValue: raw)
        else { return }
        ThemeManager.shared.current = theme
    }
```

Add `import MarkdownViewerKit` at the top of `AppDelegate.swift` if not already present.

- [ ] **Step 3: Update the checkmark for the current theme**

Add a `menuNeedsUpdate`-style handler or use `NSMenuItem.state`:

```swift
        // After building the menu, before adding to parent:
        themeMenu.delegate = self

// elsewhere:
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = ThemeManager.shared.current.rawValue
        for item in menu.items {
            if let raw = item.representedObject as? String {
                item.state = (raw == current) ? .on : .off
            }
        }
    }
}
```

If `AppDelegate` already conforms to `NSMenuDelegate`, merge the method instead of adding a second conformance.

- [ ] **Step 4: Build and smoke test**

Run: `just build && just run Fixtures/simple.md`
Expected: View menu has a Theme submenu. Picking each option re-renders the viewer and the checkmark follows. Choice persists across app launches.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewer/AppDelegate.swift
git commit -m "feat: View → Theme submenu with persistent selection"
```

---

## Task 10: `PDFPreviewWindowController` skeleton

Non-modal window with left thumbnail sidebar, center PDFView, top toolbar. This task wires up the structure and displays a generated PDF. Toolbar controls come in Task 11; live reload in Task 12.

**Files:**
- Create: `Sources/MarkdownViewer/PDFPreviewWindowController.swift`

- [ ] **Step 1: Implement skeleton**

Create `Sources/MarkdownViewer/PDFPreviewWindowController.swift`:

```swift
import AppKit
import PDFKit
import MarkdownViewerKit

@MainActor
final class PDFPreviewWindowController: NSWindowController {

    private let sourceURL: URL
    private var currentOptions: PDFExportOptions
    private let pdfView = PDFView()
    private let thumbnailView = PDFThumbnailView()
    private let exporter = PDFExporter()
    private var generationTask: Task<Void, Never>?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        self.currentOptions = PDFExportOptions.defaults
        self.currentOptions.theme = ThemeManager.shared.current

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PDF Preview — \(sourceURL.lastPathComponent)"
        window.center()
        super.init(window: window)

        setupLayout()
        regenerate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 100, height: 130)
        thumbnailView.backgroundColor = .underPageBackgroundColor
        thumbnailView.layoutMode = .vertical

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .windowBackgroundColor

        contentView.addSubview(thumbnailView)
        contentView.addSubview(pdfView)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 140),

            pdfView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Regenerate the PDF with current options and display it.
    func regenerate() {
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let markdown = try String(contentsOf: self.sourceURL, encoding: .utf8)
                let data = try await self.exporter.exportPDF(
                    markdown: markdown,
                    options: self.currentOptions,
                    documentTitle: self.sourceURL.deletingPathExtension().lastPathComponent
                )
                if Task.isCancelled { return }
                self.display(pdfData: data)
            } catch {
                NSLog("PDF generation failed: \(error)")
            }
        }
    }

    private func display(pdfData: Data) {
        // Preserve current page + scale
        let currentPageIndex: Int = pdfView.document
            .flatMap { doc in pdfView.currentPage.flatMap { doc.index(for: $0) } } ?? 0
        let scale = pdfView.scaleFactor

        let doc = PDFDocument(data: pdfData)
        pdfView.document = doc
        pdfView.scaleFactor = scale
        if let doc = doc, currentPageIndex < doc.pageCount, let page = doc.page(at: currentPageIndex) {
            pdfView.go(to: page)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && just build`
Expected: build succeeds.

- [ ] **Step 3: Wire an ad-hoc menu item for testing**

In `AppDelegate.swift`, add a temporary menu item under `File`:

```swift
        let previewItem = NSMenuItem(
            title: "PDF Preview… (dev)",
            action: #selector(showPDFPreview(_:)),
            keyEquivalent: ""
        )
        fileMenu.addItem(previewItem)
```

And the action:

```swift
    private var previewController: PDFPreviewWindowController?

    @objc func showPDFPreview(_ sender: Any?) {
        guard let url = currentDocumentURL() else { return }  // replace with your accessor
        let controller = PDFPreviewWindowController(sourceURL: url)
        controller.showWindow(self)
        previewController = controller
    }
```

(If `currentDocumentURL()` doesn't already exist, temporarily hardcode a fixture path for this dev step, e.g. `URL(fileURLWithPath: "/path/to/Fixtures/simple.md")`.)

- [ ] **Step 4: Smoke test**

Run: `just run Fixtures/simple.md`. File → "PDF Preview… (dev)".
Expected: window opens, shows single-page PDF of the fixture with thumbnail in left sidebar.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewer/PDFPreviewWindowController.swift \
        Sources/MarkdownViewer/AppDelegate.swift
git commit -m "feat(pdf): preview window skeleton with PDFView + thumbnails"
```

---

## Task 11: Preview toolbar (theme / paper / orientation / toggles)

**Files:**
- Modify: `Sources/MarkdownViewer/PDFPreviewWindowController.swift`

- [ ] **Step 1: Build toolbar**

At the top of `PDFPreviewWindowController`, add toolbar construction. Use `NSToolbar` with custom items, OR a simple `NSStackView` at the top of the content view (simpler). Pick the stack view approach:

Replace `setupLayout()` with:

```swift
    private let themePopup = NSPopUpButton()
    private let paperPopup = NSPopUpButton()
    private let orientationPopup = NSPopUpButton()
    private let startPageAtH1Checkbox = NSButton(checkboxWithTitle: "Start page at H1", target: nil, action: nil)
    private let headerCheckbox = NSButton(checkboxWithTitle: "Header", target: nil, action: nil)
    private let footerCheckbox = NSButton(checkboxWithTitle: "Footer", target: nil, action: nil)
    private let headerField = NSTextField(string: "")
    private let exportButton = NSButton(title: "Export…", target: nil, action: nil)
    private let printButton = NSButton(title: "Print…", target: nil, action: nil)

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        configureToolbarControls()
        let toolbar = NSStackView(views: [
            labeled("Theme:",       themePopup),
            labeled("Paper:",       paperPopup),
            labeled("Orientation:", orientationPopup),
            startPageAtH1Checkbox,
            headerCheckbox,
            footerCheckbox,
            labeled("Title:",       headerField),
            NSView(),   // flexible spacer
            printButton,
            exportButton,
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 100, height: 130)
        thumbnailView.backgroundColor = .underPageBackgroundColor
        thumbnailView.layoutMode = .vertical

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .windowBackgroundColor

        contentView.addSubview(toolbar)
        contentView.addSubview(thumbnailView)
        contentView.addSubview(pdfView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),

            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 140),

            pdfView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func labeled(_ label: String, _ view: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [l, view])
        stack.orientation = .horizontal
        stack.spacing = 4
        return stack
    }

    private func configureToolbarControls() {
        for theme in PDFTheme.allCases {
            themePopup.addItem(withTitle: theme.displayName)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        themePopup.selectItem(at: PDFTheme.allCases.firstIndex(of: currentOptions.theme) ?? 0)
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))

        for size in PDFExportOptions.PaperSize.allCases {
            paperPopup.addItem(withTitle: size.rawValue.uppercased())
            paperPopup.lastItem?.representedObject = size.rawValue
        }
        paperPopup.selectItem(at: PDFExportOptions.PaperSize.allCases.firstIndex(of: currentOptions.paperSize) ?? 0)
        paperPopup.target = self
        paperPopup.action = #selector(paperChanged(_:))

        for o in PDFExportOptions.Orientation.allCases {
            orientationPopup.addItem(withTitle: o.rawValue.capitalized)
            orientationPopup.lastItem?.representedObject = o.rawValue
        }
        orientationPopup.selectItem(at: PDFExportOptions.Orientation.allCases.firstIndex(of: currentOptions.orientation) ?? 0)
        orientationPopup.target = self
        orientationPopup.action = #selector(orientationChanged(_:))

        startPageAtH1Checkbox.state = currentOptions.startNewPageAtH1 ? .on : .off
        startPageAtH1Checkbox.target = self
        startPageAtH1Checkbox.action = #selector(startPageAtH1Changed(_:))

        headerCheckbox.state = currentOptions.showHeader ? .on : .off
        headerCheckbox.target = self
        headerCheckbox.action = #selector(headerChanged(_:))

        footerCheckbox.state = currentOptions.showFooter ? .on : .off
        footerCheckbox.target = self
        footerCheckbox.action = #selector(footerChanged(_:))

        headerField.stringValue = currentOptions.headerText
            ?? sourceURL.deletingPathExtension().lastPathComponent
        headerField.target = self
        headerField.action = #selector(headerTextChanged(_:))
        headerField.placeholderString = "Header text"
        headerField.widthAnchor.constraint(equalToConstant: 160).isActive = true

        exportButton.target = self
        exportButton.action = #selector(exportPressed(_:))
        printButton.target = self
        printButton.action = #selector(printPressed(_:))
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let t = PDFTheme(rawValue: raw) else { return }
        currentOptions.theme = t
        applyThemeDefaultsIfUserHasNotCustomized()
        ThemeManager.shared.current = t   // also update screen viewer
        regenerate()
    }

    @objc private func paperChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let s = PDFExportOptions.PaperSize(rawValue: raw) else { return }
        currentOptions.paperSize = s
        regenerate()
    }

    @objc private func orientationChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let o = PDFExportOptions.Orientation(rawValue: raw) else { return }
        currentOptions.orientation = o
        regenerate()
    }

    @objc private func startPageAtH1Changed(_ sender: NSButton) {
        currentOptions.startNewPageAtH1 = (sender.state == .on)
        regenerate()
    }

    @objc private func headerChanged(_ sender: NSButton) {
        currentOptions.showHeader = (sender.state == .on)
        regenerate()
    }

    @objc private func footerChanged(_ sender: NSButton) {
        currentOptions.showFooter = (sender.state == .on)
        regenerate()
    }

    @objc private func headerTextChanged(_ sender: NSTextField) {
        currentOptions.headerText = sender.stringValue.isEmpty ? nil : sender.stringValue
        regenerate()
    }

    private func applyThemeDefaultsIfUserHasNotCustomized() {
        currentOptions.showHeader = currentOptions.theme.defaultShowHeader
        currentOptions.showFooter = currentOptions.theme.defaultShowFooter
        headerCheckbox.state = currentOptions.showHeader ? .on : .off
        footerCheckbox.state = currentOptions.showFooter ? .on : .off
    }

    @objc private func exportPressed(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".pdf"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let data = self.pdfView.document?.dataRepresentation() else { return }
            try? data.write(to: url)
        }
    }

    @objc private func printPressed(_ sender: Any?) {
        guard let doc = pdfView.document else { return }
        let op = doc.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false)
        op?.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // Auto-pick the user's locale default for paper size on first open.
    private func seedPaperSizeFromLocale() {
        let sys = NSPrintInfo.shared.paperSize
        let a4Height: CGFloat = 842
        currentOptions.paperSize = (abs(sys.height - a4Height) < abs(sys.height - 792)) ? .a4 : .letter
    }
```

Call `seedPaperSizeFromLocale()` in `init` before `regenerate()`.

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && just build`
Expected: build succeeds.

- [ ] **Step 3: Smoke test**

Run: `just run Fixtures/simple.md`. Open the preview window.
Expected:
- All popups visible
- Switching theme re-renders the PDF *and* the viewer behind it
- Switching paper / orientation re-renders
- Toggling "Start page at H1" re-renders (no visible change on `simple.md`; try `Fixtures/mixed.md`)
- Export… writes a PDF
- Print… opens the system print panel

- [ ] **Step 4: Commit**

```bash
git add Sources/MarkdownViewer/PDFPreviewWindowController.swift
git commit -m "feat(pdf): preview toolbar with theme, paper, orientation, chrome, print/export"
```

---

## Task 12: Live reload on source file change

**Files:**
- Modify: `Sources/MarkdownViewer/PDFPreviewWindowController.swift`

- [ ] **Step 1: Add FileWatcher**

At the top of the class, add:

```swift
    private let fileWatcher = FileWatcher()
```

In `init`, after `super.init`:

```swift
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in self?.regenerate() }
        }
        fileWatcher.watch(path: sourceURL.path)
```

In `deinit` (add one if not present):

```swift
    deinit { fileWatcher.stop() }
```

- [ ] **Step 2: Build**

Run: `just build`
Expected: build succeeds.

- [ ] **Step 3: Smoke test**

Run: `just run Fixtures/simple.md`. Open preview. In another shell:

```bash
echo "\n\nNewly added paragraph." >> Fixtures/simple.md
```

Expected: preview regenerates within ~1s, now showing the extra paragraph. Revert the fixture after.

- [ ] **Step 4: Commit**

```bash
git add Sources/MarkdownViewer/PDFPreviewWindowController.swift
git commit -m "feat(pdf): preview window auto-refreshes on source file change"
```

---

## Task 13: Wire ⌘P and File → Export as PDF… in the main menu

**Files:**
- Modify: `Sources/MarkdownViewer/AppDelegate.swift`
- Modify: `Sources/MarkdownViewer/ViewerWindowController.swift`

Replace the dev-only menu item from Task 10 with the production wiring.

- [ ] **Step 1: Add `File → Export as PDF…` and ⌘P in File menu**

In `AppDelegate.swift`, where the File menu is built, add:

```swift
        let printItem = NSMenuItem(
            title: "Print…",
            action: #selector(printDocument(_:)),
            keyEquivalent: "p"
        )
        printItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(printItem)

        let exportItem = NSMenuItem(
            title: "Export as PDF…",
            action: #selector(exportAsPDF(_:)),
            keyEquivalent: "p"
        )
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportItem)
```

And the actions on `AppDelegate` (delete the dev `showPDFPreview`):

```swift
    @objc func printDocument(_ sender: Any?) {
        activeViewerWindowController()?.openPDFPreview(primingAction: .print)
    }

    @objc func exportAsPDF(_ sender: Any?) {
        activeViewerWindowController()?.openPDFPreview(primingAction: .export)
    }

    private func activeViewerWindowController() -> ViewerWindowController? {
        NSApp.keyWindow?.windowController as? ViewerWindowController
    }
```

- [ ] **Step 2: Add `openPDFPreview` on `ViewerWindowController`**

In `ViewerWindowController.swift`, add:

```swift
    enum PDFPrimingAction { case print, export }

    private var pdfPreviewController: PDFPreviewWindowController?

    func openPDFPreview(primingAction: PDFPrimingAction) {
        guard selectedIndex >= 0, selectedIndex < openFiles.count else {
            NSSound.beep()
            return
        }
        let url = openFiles[selectedIndex].url
        let controller = pdfPreviewController ?? PDFPreviewWindowController(sourceURL: url)
        pdfPreviewController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(nil)
        switch primingAction {
        case .print:  controller.focusPrintButton()
        case .export: controller.focusExportButton()
        }
    }
```

And in `PDFPreviewWindowController`:

```swift
    func focusPrintButton()  { window?.makeFirstResponder(printButton) }
    func focusExportButton() { window?.makeFirstResponder(exportButton) }
```

- [ ] **Step 3: Remove the dev menu item from Task 10**

Delete the "PDF Preview… (dev)" menu item and its `showPDFPreview(_:)` action from `AppDelegate.swift`.

- [ ] **Step 4: Build and smoke test**

Run: `just build && just run Fixtures/simple.md`
- ⌘P → preview window opens with Print button focused (pressing Return runs system print)
- ⌘⇧P → preview window opens with Export button focused
- Closing preview window while viewer is still open is fine
- Reopening preview reuses the instance (so live reload keeps working)

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownViewer/AppDelegate.swift \
        Sources/MarkdownViewer/ViewerWindowController.swift \
        Sources/MarkdownViewer/PDFPreviewWindowController.swift
git commit -m "feat(pdf): File → Print (⌘P) and Export as PDF (⌘⇧P)"
```

---

## Task 14: Warning badge for scaled-down content

**Files:**
- Modify: `Sources/MarkdownViewerKit/PDFExporter.swift`
- Modify: `Sources/MarkdownViewer/PDFPreviewWindowController.swift`

The goal: after generating, inspect pages for images whose rendered height is <70% of the page height (heuristic proxy for "this image got shrunk to fit"), mark those page indexes, and overlay a small warning glyph on those thumbnails.

- [ ] **Step 1: Extend `PDFExporter` to return scaled-page indexes**

Change the return type to a struct, or add a second method. Add a struct:

```swift
public struct PDFExportResult: Sendable {
    public let data: Data
    /// Page indexes (0-based) where at least one image was scaled to <70% of its natural area.
    public let scaledPageIndexes: [Int]
}
```

Replace `exportPDF(...) -> Data` with `exportPDF(...) -> PDFExportResult`. For now, leave `scaledPageIndexes` empty; we'll populate it below.

Inside `exportPDF`, after the HTML loads and before `createPDF`, query the DOM:

```swift
        let scaledPages = await detectScaledImages(in: webView, pageHeight: pageSize.height)
```

Add the helper:

```swift
    private func detectScaledImages(in webView: WKWebView, pageHeight: CGFloat) async -> [Int] {
        let js = """
        (function() {
            var pages = new Set();
            var imgs = document.querySelectorAll('img, svg, .mermaid');
            imgs.forEach(function(el) {
                var rect = el.getBoundingClientRect();
                var natural = el.naturalWidth ? (el.naturalWidth * el.naturalHeight)
                                              : (el.dataset.naturalArea || 0);
                var rendered = rect.width * rect.height;
                if (natural > 0 && rendered > 0 && (rendered / natural) < 0.49) { // ~70% linear ≈ 49% area
                    var pageIndex = Math.floor((rect.top + window.scrollY) / \(pageHeight));
                    pages.add(pageIndex);
                }
            });
            return Array.from(pages);
        })();
        """
        return await withCheckedContinuation { (c: CheckedContinuation<[Int], Never>) in
            webView.evaluateJavaScript(js) { result, _ in
                c.resume(returning: (result as? [Int]) ?? [])
            }
        }
    }
```

Update every caller of `exportPDF` to use `.data` (`PDFPreviewWindowController`, tests). Tests use `result.data`.

Update tests:

```swift
        let result = try await exporter.exportPDF(markdown: markdown, options: .defaults, documentTitle: "simple")
        let doc = try XCTUnwrap(PDFDocument(data: result.data))
```

- [ ] **Step 2: Overlay warning icons in the preview window**

In `PDFPreviewWindowController`, add a property:

```swift
    private var warningPageIndexes: Set<Int> = []
```

After generation, set the property from the result and trigger a custom drawing on thumbnails. Subclassing `PDFThumbnailView` for per-thumbnail overlays is finicky — simplest approach: overlay a small table view on top of the thumbnail column showing warning icons aligned to warning thumbnails, OR draw via a child `NSView` that iterates `thumbnailView.subviews`.

**Pragmatic approach:** add a vertical `NSStackView` of `NSImageView`s next to the thumbnail column, one per page, sized to match. If a page is in `warningPageIndexes`, show `NSImage(systemSymbolName: "exclamationmark.triangle.fill", …)`; else empty.

```swift
    private let warningColumn = NSStackView()

    // inside setupLayout after configuring thumbnailView
    warningColumn.orientation = .vertical
    warningColumn.spacing = 0
    warningColumn.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(warningColumn)
    NSLayoutConstraint.activate([
        warningColumn.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
        warningColumn.topAnchor.constraint(equalTo: thumbnailView.topAnchor),
        warningColumn.widthAnchor.constraint(equalToConstant: 20),
    ])
    // adjust pdfView.leadingAnchor to warningColumn.trailingAnchor
```

Add a rebuild method:

```swift
    private func rebuildWarningColumn(pageCount: Int) {
        warningColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for i in 0..<pageCount {
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            if warningPageIndexes.contains(i) {
                iv.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                   accessibilityDescription: "Scaled content")
                iv.contentTintColor = .systemOrange
                iv.toolTip = "Content on this page was scaled to fit."
            }
            iv.heightAnchor.constraint(equalToConstant: 138).isActive = true
            warningColumn.addArrangedSubview(iv)
        }
    }
```

Call `rebuildWarningColumn(pageCount: doc.pageCount)` from `display(pdfData:)`.

- [ ] **Step 3: Build and smoke test**

Create `Fixtures/pdf-huge-image.md` (in repo root `Fixtures/`, not in tests) with a large image reference. Open preview.
Expected: the page containing the huge image has an orange warning triangle beside its thumbnail.

- [ ] **Step 4: Commit**

```bash
git add Sources/MarkdownViewerKit/PDFExporter.swift \
        Sources/MarkdownViewer/PDFPreviewWindowController.swift \
        Tests/MarkdownViewerKitTests/PDFExporterTests.swift
git commit -m "feat(pdf): warning badge for pages with scaled-down content"
```

---

## Task 15: Manual QA checklist + documentation

**Files:**
- Modify: `README.md` (add PDF Export section)
- Create: `docs/manual-qa/pdf-export.md` (new)

- [ ] **Step 1: Run the manual QA checklist**

Go through every item on a real build. Any failure blocks this task.

Create `docs/manual-qa/pdf-export.md`:

```markdown
# PDF Export — Manual QA checklist

Run against the latest build. Tick every item.

## Setup
- [ ] `just clean && just build && just run Fixtures/mixed.md`

## Preview window
- [ ] ⌘P opens the preview window; Print button is focused (Return triggers system print)
- [ ] ⌘⇧P opens the preview window; Export button is focused (Return shows Save panel)
- [ ] Closing the preview doesn't affect the viewer
- [ ] Reopening after close creates a working instance
- [ ] Thumbnails appear down the left side

## Theming
- [ ] View → Theme → GitHub: viewer and preview both update immediately
- [ ] Same for Technical Paper, same for Apple Documentation
- [ ] Changing theme in preview toolbar also updates the viewer
- [ ] Theme choice persists across app restarts

## Pagination
- [ ] `Fixtures/mixed.md` renders with sensible page breaks (no heading alone at bottom of a page)
- [ ] Images in fixture remain whole (no split across pages)
- [ ] Mermaid diagram in fixture remains whole
- [ ] "Start page at H1" toggle: each H1 begins on a new page
- [ ] A 500-line code block fixture: code splits across pages (confirmed acceptable fallback)

## Header/footer
- [ ] Header toggle hides/shows the running title
- [ ] Footer toggle hides/shows the page numbers
- [ ] Editing the header text field updates the PDF
- [ ] Theme defaults are applied when switching themes

## Paper / orientation
- [ ] Switching Letter ↔ A4 regenerates with correct size
- [ ] Switching Portrait ↔ Landscape regenerates correctly

## Live reload
- [ ] Edit the source `.md` externally; preview regenerates within ~1 second
- [ ] Current page index is preserved across regeneration

## Export / print
- [ ] Export saves a valid PDF that opens in Preview.app with identical rendering
- [ ] Print opens the system print panel and produces identical output

## Warning badges
- [ ] A fixture with a huge image shows the orange triangle on the affected page's thumbnail
- [ ] The badge disappears when the image fits naturally
```

- [ ] **Step 2: Update README**

Append to `README.md`:

```markdown
## Export as PDF

MarkdownViewer can export any document as a presentable, WYSIWYG PDF:

- **⌘P** — Print…
- **⌘⇧P** — Export as PDF…

Both open a live PDF preview window. Pick one of three document themes
(GitHub, Technical Paper, Apple Documentation), paper size (Letter / A4),
orientation, and optional running header/footer. The preview updates in
real time as you edit the source. Images, diagrams, and short code blocks
are never split across pages; very long code blocks fall back to splitting.
```

- [ ] **Step 3: Commit**

```bash
git add docs/manual-qa/pdf-export.md README.md
git commit -m "docs: PDF export QA checklist and README section"
```

---

## Self-review

After completing all tasks, verify:

- [ ] Every spec section (triggers, preview window, themes, pagination rules, error handling, testing, file layout) is implemented by at least one task above.
- [ ] All tests pass: `just test`
- [ ] Manual QA checklist in Task 15 all green
- [ ] No `// TODO` / `// FIXME` left in new code
- [ ] `git log` shows one focused commit per task (no squashed catch-alls)
