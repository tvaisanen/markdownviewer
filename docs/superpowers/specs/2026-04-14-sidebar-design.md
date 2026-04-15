# Sidebar File Panel — Design Spec

**Date:** 2026-04-14
**Status:** Approved
**Depends on:** MVP (complete)

## Overview

Replace native macOS window tabs with an `NSSplitViewController`-based sidebar listing open files. Selecting a file in the sidebar switches the content pane (Finder-style — one content area, sidebar navigates it). The sidebar collapses/expands natively via `toggleSidebar:`.

## Architecture

### New Classes

| Class | Target | Responsibility |
|-------|--------|---------------|
| `MainSplitViewController` | MarkdownViewer | `NSSplitViewController` owning sidebar + content. Configures sidebar item with `canCollapse = true`, `.preferResizingSplitViewWithFixedSiblings` |
| `SidebarViewController` | MarkdownViewer | `NSViewController` with `NSTableView` listing open files. Notifies delegate on selection change. "+" button to open files |
| `ContentViewController` | MarkdownViewer | `NSViewController` hosting `WebContentView`. Shows empty state when no file selected |

### Modified Classes

| Class | Changes |
|-------|---------|
| `ViewerWindowController` | Owns `MainSplitViewController` instead of directly owning `WebContentView`. Manages open files list, `FileWatcher` per file, coordinates sidebar selection → content rendering |
| `ViewerWindow` | Remove `.tabbingMode = .preferred`. Add `NSToolbar` with sidebar toggle button |
| `AppDelegate` | Remove tabbing logic (`addTabbedWindow`). Route file opens to `ViewerWindowController.openFile(url:)` |

### Unchanged

`MarkdownViewerKit` framework (WebContentView, MarkdownRenderer, FileWatcher, DiagramProcessor, MermaidRenderer, PlantUMLRenderer) — no changes needed.

## Sidebar UI

- `NSTableView` with single column, no header
- Each row: primary text = filename (e.g., `mixed.md`), secondary text = parent directory in smaller gray font (e.g., `~/projects/docs`)
- Selection highlights row and switches content pane
- Close file: right-click context menu with "Close" item, or select + `Delete` key
- "+" button (SF Symbol `plus`) in sidebar header area, triggers `NSOpenPanel`
- Sidebar toggle: `NSToolbar` button with SF Symbol `sidebar.leading`, wired to `toggleSidebar:` action, keyboard shortcut `Cmd+Ctrl+S`

## Content Area

- Hosts `WebContentView` (existing, unchanged)
- When a file is selected: renders and displays that file
- Empty state: centered gray text "Open a file to get started" with `Cmd+O` hint
- Window title updates to selected file's name

## Data Flow

```
User opens file (CLI / Apple Event / Open panel)
  → AppDelegate calls ViewerWindowController.openFile(url)
  → ViewerWindowController adds URL to open files list
  → SidebarViewController refreshes table, selects new row
  → ViewerWindowController renders markdown → HTML for selected file
  → ContentViewController.webContentView loads HTML
  → FileWatcher starts watching the new file

User clicks different file in sidebar
  → SidebarViewController selection change callback
  → ViewerWindowController switches to that file
  → Re-renders and loads HTML into same ContentViewController

User closes file (context menu or delete key on sidebar row)
  → ViewerWindowController removes URL from list, stops FileWatcher
  → SidebarViewController refreshes table
  → If closed file was selected, select adjacent file (or show empty state)

File changes on disk
  → FileWatcher fires onChange
  → If changed file is currently selected, re-render and reload
  → If not selected, mark as stale (re-render when user selects it)
```

## Stale File Optimization

When a non-selected file changes on disk, mark it as "stale" instead of re-rendering immediately. Re-render only when the user selects it. This avoids unnecessary PlantUML CLI calls and rendering work for files the user isn't looking at.

## Out of Scope

- File tree / directory browsing (sidebar only shows open files)
- Drag-and-drop reordering of sidebar items
- Bookmarks, annotations, highlights
