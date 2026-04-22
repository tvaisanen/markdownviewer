# MarkdownViewer

A native macOS markdown viewer with Mermaid diagram support.

## Install

```
brew tap tvaisanen/tap
brew install --cask mdview
```

This installs `MarkdownViewer.app` to `/Applications` and the `mdview` CLI to your PATH.

## Usage

```
mdview                     # Launch or activate MarkdownViewer
mdview README.md           # Open a file
mdview doc1.md doc2.md     # Open multiple files
mdview --help              # Show usage
```

## Features

- GitHub Flavored Markdown (tables, strikethrough, autolinks, task lists)
- Mermaid diagram rendering with selectable themes
- Sidebar with file management and hover auto-show
- Table of Contents navigation
- Content brightness control
- Window frame persistence across launches
- Live file watching — edits reload automatically

## Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen just
xcodegen generate
just build
```

## Export as PDF

MarkdownViewer exports any document as a presentable, WYSIWYG PDF:

- **⌘P** — Print…
- **⌘⇧P** — Export as PDF…

Both open a live preview window. Pick one of three document themes
(GitHub, Technical Paper, Apple Documentation), paper size (Letter or A4),
orientation, and optional running header/footer. The preview updates
in real time as you edit the source markdown. Images, diagrams, and
short code blocks are never split across pages; very long code blocks
fall back to splitting.

## License

MIT
