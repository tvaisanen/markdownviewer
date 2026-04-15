# MarkdownViewer — Implementation Design Spec

**Date:** 2026-04-14
**Status:** Approved
**Base spec:** `docs/design.md`

## Overview

Native macOS AppKit application that renders markdown files with Mermaid and PlantUML diagram support. `open foo.md` opens a native window with rendered content. No browser, no extension, no CLI pipeline.

## Build System

Xcode project (`.xcodeproj`) with two targets:

- **MarkdownViewer** — macOS Application target. Thin AppKit shell: `NSApplicationDelegate` bootstrap, window/tab management, file open handling.
- **MarkdownViewerKit** — macOS Framework target. All rendering logic. Shared with QuickLook plugin in a future phase.

**Dependencies:**
- swift-cmark (SPM via Xcode) — markdown to HTML
- mermaid.min.js (bundled in Resources) — client-side diagram rendering
- plantuml CLI (external, optional) — server-side SVG generation

**Minimum deployment target:** macOS 14 (Sonoma)

## Architecture

### MarkdownViewerKit (Framework)

| Class | Responsibility |
|-------|---------------|
| `MarkdownRenderer` | Orchestrates full pipeline: markdown string in, HTML string out |
| `DiagramProcessor` | Regex scan for ` ```mermaid ` / ` ```plantuml ` fenced code blocks, routes to renderers |
| `MermaidRenderer` | Wraps content in `<div class="mermaid">` for client-side JS rendering |
| `PlantUMLRenderer` | Shells out to `plantuml -tsvg -pipe`, returns inline SVG. 10s timeout. Placeholder if binary not found |
| `FileWatcher` | `DispatchSource.makeFileSystemObjectSource` on file descriptor, `.write` events, 200ms debounce |
| `WebContentView` | `WKWebView` wrapper, loads HTML, handles scroll position preservation on reload |

### MarkdownViewer (App)

| Class | Responsibility |
|-------|---------------|
| `AppDelegate` | `NSApplicationDelegate`, handles `application(_:openFiles:)`, manages single-window-with-tabs |
| `ViewerWindow` | `NSWindow` subclass, `.tabbingMode = .preferred`, title = filename |
| `ViewerWindowController` | Owns `WebContentView` + `FileWatcher`, coordinates file-change → re-render → reload cycle |

## Rendering Pipeline

```
file.md → UTF-8 string
  → DiagramProcessor scans for fenced code blocks
  → PlantUML blocks: pipe to `plantuml -tsvg -pipe` → inline <svg>
  → Mermaid blocks: wrap in <div class="mermaid">
  → Remaining markdown: swift-cmark → HTML
  → Inject into template.html (includes mermaid.min.js + style.css)
  → WKWebView.loadHTMLString()
  → Mermaid.js runs client-side, renders <div class="mermaid"> → SVG
```

### Diagram Handling

**Mermaid:**
- Bundled `mermaid.min.js` in app Resources
- Fenced ` ```mermaid ` blocks → `<div class="mermaid">{content}</div>`
- `mermaid.initialize({ startOnLoad: true, theme: 'default' })` on page load
- Dark mode: re-initialize with `theme: 'dark'` on appearance change

**PlantUML:**
- External `plantuml` binary (user installs via `brew install plantuml`)
- Fenced ` ```plantuml ` blocks → extract source, pipe to `plantuml -tsvg -pipe`
- Inline resulting `<svg>` in HTML output
- Binary not found: render gray placeholder with install instructions
- 10-second timeout per diagram, show error on timeout

## Resources

Bundled in app bundle (no CDN):
- `mermaid.min.js` — Mermaid rendering engine
- `template.html` — HTML wrapper: `<head>` with JS/CSS includes, `<body>` content placeholder
- `style.css` — typography, code block styling, `prefers-color-scheme` media queries

## Window Management

- `NSWindow` with `.tabbingMode = .preferred` — macOS native tab bar
- Each open file = one tab, window/tab title = filename
- `open foo.md bar.md` → both files as tabs in single window
- App already running + `open baz.md` → `application(_:openFiles:)` adds tab to existing window
- `Info.plist` declares `public.markdown` UTI and document types for Finder integration

## Live Reload

- `FileWatcher` uses `DispatchSource.makeFileSystemObjectSource` on open file descriptors
- Watches `.write` events
- 200ms debounce (editors write temp file + rename)
- On change: re-read file → re-run rendering pipeline → reload WKWebView
- Scroll preservation: read `window.scrollY` via JS eval before reload, restore after `webView(_:didFinish:)` callback

## Dark/Light Mode

- CSS: `prefers-color-scheme` media queries in `style.css`
- Mermaid: observe `NSApp.effectiveAppearance` changes → JS call to `mermaid.initialize({ theme: 'dark'|'default' })` → re-render
- WKWebView respects system appearance automatically

## QuickLook Plugin (future phase)

- Separate `.appex` target in the same Xcode project
- Uses `MarkdownViewerKit` framework for rendering
- `QLPreviewProvider` subclass loads rendered HTML into WKWebView
- Not part of MVP implementation

## Out of Scope

- Bookmarks, annotations, highlights
- D2, GraphViz diagram support
- App Store distribution
- Editor/authoring features
