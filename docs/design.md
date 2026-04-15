# MarkdownViewer — Design Spec

**Date:** 2026-04-14
**Status:** Draft
**Repo:** `tvaisanen/markdownviewer` (standalone, not in monorepo)

## Problem

Opening a `.md` file with diagrams (Mermaid, PlantUML) requires launching a browser, VS Code extension, or a CLI pipeline. There's no macOS app where `open foo.md` just works — rendered markdown with diagrams in a native window.

## Scope — MVP

Renderer only. No annotations, bookmarks, or highlights (planned for later iteration).

### In scope

- `open foo.md` opens a native macOS window with rendered markdown + diagrams
- Mermaid diagram rendering (client-side JS in WKWebView)
- PlantUML diagram rendering (shell out to `plantuml` CLI)
- Tabbed window management (macOS native tabbing)
- Live reload on file change
- Dark/light mode support
- QuickLook plugin (same rendering engine)

### Out of scope (future)

- Bookmarks sidebar (cross-file, navigable list)
- Text highlights with comments (annotations stored in sidecar SQLite, file-version-aware with fuzzy re-anchoring)
- D2, GraphViz diagram support
- App Store distribution

## Architecture

### Project structure

```
MarkdownViewer/
├── Package.swift
├── Sources/
│   ├── MarkdownViewer/              # CLI entry point
│   │   └── main.swift               # NSApplication bootstrap, open file(s)
│   └── MarkdownViewerKit/           # Shared rendering engine
│       ├── MarkdownRenderer.swift   # MD → HTML (cmark + diagram pre-processing)
│       ├── DiagramProcessor.swift   # Detect & route diagram code blocks
│       ├── MermaidRenderer.swift    # Injects mermaid.min.js, renders client-side
│       ├── PlantUMLRenderer.swift   # Shells out to `plantuml -tsvg -pipe`
│       ├── FileWatcher.swift        # DispatchSource-based live reload
│       ├── ViewerWindow.swift       # NSWindow + tab management
│       └── WebContentView.swift     # WKWebView setup
├── Resources/
│   ├── mermaid.min.js               # Bundled Mermaid JS (no CDN)
│   ├── template.html               # Base HTML wrapper
│   └── style.css                    # Typography, code blocks, dark/light
└── QuickLook/                       # QuickLook plugin target (appex)
```

Two targets:
- **MarkdownViewer** — executable, thin CLI that bootstraps NSApplication and opens windows
- **MarkdownViewerKit** — library with all rendering logic, shared with QuickLook plugin

### Rendering pipeline

```
file.md
  → read UTF-8
  → scan code blocks for diagram fences
  → PlantUML blocks: pipe through `plantuml -tsvg -pipe` → inline <svg>
  → Mermaid blocks: wrap in <div class="mermaid">
  → remaining markdown: parse with cmark → HTML
  → inject into template.html (includes mermaid.min.js)
  → WKWebView.loadHTMLString()
  → Mermaid.js runs client-side, renders <div class="mermaid"> → SVG
```

### Diagram rendering

**Mermaid:**
- Bundle `mermaid.min.js` in Resources
- Code blocks with ```mermaid fence → `<div class="mermaid">` in HTML
- Mermaid.js initializes on page load with `mermaid.initialize({ startOnLoad: true, theme: 'default' })`
- Dark mode: re-initialize with `theme: 'dark'` when system appearance changes

**PlantUML:**
- Requires `plantuml` installed (`brew install plantuml`)
- Code blocks with ```plantuml fence → extract source, pipe to `plantuml -tsvg -pipe`
- Embed resulting SVG inline in HTML
- If `plantuml` binary not found: render a gray placeholder box with message "PlantUML not installed — run: brew install plantuml"
- Timeout: 10 seconds per diagram, show error on timeout

### Window management

- `NSWindow` with `.tabbingMode = .preferred`
- Each open file = one tab, window/tab title = filename
- `open foo.md bar.md` → both files as tabs in one window
- If app already running, `open baz.md` → adds tab to existing window via `NSApp` activation
- Register `public.markdown` UTI so system routes `.md` files to the app

### File watching

- `DispatchSource.makeFileSystemObjectSource` on open file descriptors, watching `.write` events
- On change: re-read file, re-run pipeline, reload WKWebView
- Debounce: 200ms (editors write temp + rename)
- Scroll position preserved: read `window.scrollY` via JS before reload, restore after load

### Dark/light mode

- CSS `prefers-color-scheme` media query in `style.css`
- Mermaid theme toggled via `NSApp.effectiveAppearance` observation → JS call to re-initialize Mermaid
- WKWebView respects system appearance automatically

### QuickLook plugin

- Separate target (`.appex` bundle)
- Uses `MarkdownViewerKit` for rendering
- Generates HTML string, loads in a QLPreviewProvider's WKWebView
- Spacebar in Finder renders markdown + diagrams

## Dependencies

| Dependency | Purpose | Source |
|-----------|---------|--------|
| swift-cmark | Markdown → HTML | SPM: apple/swift-cmark |
| mermaid.min.js | Mermaid diagram rendering | Bundled JS file |
| plantuml | PlantUML diagram rendering | External: `brew install plantuml` |

## Prerequisites

- macOS 14+ (Sonoma) — for modern WKWebView and QuickLook APIs
- `plantuml` installed via Homebrew (optional — app works without it, PlantUML blocks show placeholder)

## Future iterations

1. **Annotations** — bookmarks sidebar, text highlights with comments, sidecar SQLite storage, file-version-aware (SHA-256 hash tracking, fuzzy re-anchoring for drifted content)
2. **Additional diagram formats** — D2, GraphViz
3. **App Store distribution**
