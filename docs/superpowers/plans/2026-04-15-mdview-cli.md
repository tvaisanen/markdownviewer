# mdview CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a standalone `mdview` CLI binary that validates file arguments and launches the MarkdownViewer.app, returning control to the terminal immediately.

**Architecture:** A lightweight Swift command-line tool that validates file existence, prints help/usage, and delegates to `open -a MarkdownViewer` for app launch. The .app's own `main.swift` is reverted to remove CLI validation (that's the CLI's job now). Bundle IDs are migrated from `com.tvaisanen` to `com.slantedt`.

**Tech Stack:** Swift 6, XcodeGen (project.yml), Foundation (Process/FileManager)

---

### Task 1: Migrate bundle ID from com.tvaisanen to com.slantedt

**Files:**
- Modify: `project.yml:26,49`
- Modify: `Sources/MarkdownViewer/Info.plist:27`
- Modify: `Sources/MarkdownViewerKit/Info.plist:10`
- Modify: `Sources/MarkdownViewerKit/FileWatcher.swift:9`

- [ ] **Step 1: Update project.yml**

Change both bundle identifiers:

```yaml
# Line 26
CFBundleIdentifier: com.slantedt.markdownviewerkit
# Line 49
CFBundleIdentifier: com.slantedt.markdownviewer
```

- [ ] **Step 2: Update Info.plist files**

In `Sources/MarkdownViewer/Info.plist`, change:
```xml
<string>com.slantedt.markdownviewer</string>
```

In `Sources/MarkdownViewerKit/Info.plist`, change:
```xml
<string>com.slantedt.markdownviewerkit</string>
```

- [ ] **Step 3: Update FileWatcher dispatch queue label**

In `Sources/MarkdownViewerKit/FileWatcher.swift:9`, change:
```swift
private let queue = DispatchQueue(label: "com.slantedt.markdownviewer.filewatcher")
```

- [ ] **Step 4: Regenerate Xcode project and build**

```bash
xcodegen generate
xcodebuild -scheme MarkdownViewer -configuration Debug -derivedDataPath build build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Verify new bundle ID**

```bash
defaults read com.slantedt.markdownviewer 2>&1
```

Launch the app, resize the window, quit, then run the above. The key `NSWindow Frame ViewerWindow` should appear under the new domain.

- [ ] **Step 6: Clean up old defaults domain**

```bash
defaults delete com.tvaisanen.markdownviewer 2>/dev/null
```

- [ ] **Step 7: Commit**

```bash
git add project.yml Sources/MarkdownViewer/Info.plist Sources/MarkdownViewerKit/Info.plist Sources/MarkdownViewerKit/FileWatcher.swift
git commit -m "chore: migrate bundle ID from com.tvaisanen to com.slantedt"
```

---

### Task 2: Revert CLI validation from main.swift

**Files:**
- Modify: `Sources/MarkdownViewer/main.swift`
- Modify: `Sources/MarkdownViewer/AppDelegate.swift`

The .app should not do file validation — that's the CLI's job. Files passed via `open -a` are delivered through Apple Events (`application(_:openFiles:)`), and AppDelegate already handles those.

- [ ] **Step 1: Revert main.swift to its original form**

```swift
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Restore fileExists filter in AppDelegate**

In `applicationDidFinishLaunching`, the command-line args handler should keep the `fileExists` filter as a safety net for direct binary invocation:

```swift
let fileURLs = args
    .map { URL(fileURLWithPath: $0) }
    .filter { FileManager.default.fileExists(atPath: $0.path) }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme MarkdownViewer -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/MarkdownViewer/main.swift Sources/MarkdownViewer/AppDelegate.swift
git commit -m "revert: remove CLI validation from app main.swift"
```

---

### Task 3: Create the mdview CLI target

**Files:**
- Create: `Sources/mdview/main.swift`
- Modify: `project.yml` (add new target)

- [ ] **Step 1: Create the CLI source file**

Create `Sources/mdview/main.swift`:

```swift
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

    return process.terminationStatus
}

exit(main())
```

- [ ] **Step 2: Add the CLI target to project.yml**

Add after the `MarkdownViewerKitTests` target:

```yaml
  mdview:
    type: tool
    platform: macOS
    sources:
      - Sources/mdview
    settings:
      SWIFT_VERSION: "6.0"
```

- [ ] **Step 3: Regenerate Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 4: Build the CLI**

```bash
xcodebuild -scheme mdview -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Test --help**

```bash
./build/Build/Products/Debug/mdview --help
```

Expected output:
```
mdview — open Markdown files in MarkdownViewer

USAGE
    mdview [file ...]
    mdview --help | -h
    mdview --version | -v

EXAMPLES
    mdview                     Launch or activate MarkdownViewer
    mdview README.md           Open a file
    mdview doc1.md doc2.md     Open multiple files
```

- [ ] **Step 6: Test --version**

```bash
./build/Build/Products/Debug/mdview --version
```

Expected: `mdview 0.1.0`

- [ ] **Step 7: Test file-not-found**

```bash
./build/Build/Products/Debug/mdview /tmp/nonexistent.md 2>&1; echo "exit: $?"
```

Expected:
```
error: file not found: /tmp/nonexistent.md
exit: 1
```

- [ ] **Step 8: Test no-args launch**

```bash
./build/Build/Products/Debug/mdview; echo "exit: $?"
```

Expected: MarkdownViewer.app launches (or activates if already running), terminal returns immediately with `exit: 0`.

- [ ] **Step 9: Test with a valid file**

```bash
echo "# Test" > /tmp/mdview-test.md
./build/Build/Products/Debug/mdview /tmp/mdview-test.md; echo "exit: $?"
rm /tmp/mdview-test.md
```

Expected: MarkdownViewer opens the file, terminal returns `exit: 0`.

- [ ] **Step 10: Commit**

```bash
git add Sources/mdview/main.swift project.yml
git commit -m "feat: add mdview CLI tool for launching MarkdownViewer from terminal"
```

---

### Task 4: Regenerate Xcode project and final verification

**Files:**
- Modify: `MarkdownViewer.xcodeproj/` (regenerated)

- [ ] **Step 1: Regenerate and build all targets**

```bash
xcodegen generate
xcodebuild -scheme MarkdownViewer -configuration Debug -derivedDataPath build build 2>&1 | tail -3
xcodebuild -scheme mdview -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

Expected: Both BUILD SUCCEEDED

- [ ] **Step 2: Full integration test**

```bash
# Kill any running instance
killall MarkdownViewer 2>/dev/null

# Launch via CLI with no args
./build/Build/Products/Debug/mdview
sleep 2

# App should be running
pgrep -x MarkdownViewer > /dev/null && echo "app running" || echo "app NOT running"

# Open a file
echo "# Hello" > /tmp/mdview-final.md
./build/Build/Products/Debug/mdview /tmp/mdview-final.md

# Clean up
sleep 1
killall MarkdownViewer 2>/dev/null
rm /tmp/mdview-final.md
```

- [ ] **Step 3: Verify bundle ID in built app**

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" build/Build/Products/Debug/MarkdownViewer.app/Contents/Info.plist
```

Expected: `com.slantedt.markdownviewer`

- [ ] **Step 4: Commit regenerated project**

```bash
git add MarkdownViewer.xcodeproj
git commit -m "chore: regenerate Xcode project with mdview target and new bundle ID"
```
