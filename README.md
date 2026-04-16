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

## License

MIT
