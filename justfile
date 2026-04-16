sign_identity := "Developer ID Application: Toni Väisänen (42JQ8WHJ28)"
tap_repo := env("HOME") / "projects/homebrew-tap"
build_dir := "build/Build/Products"

# Build debug app and CLI
build:
    xcodegen generate
    xcodebuild -scheme MarkdownViewer -configuration Debug -derivedDataPath build build
    xcodebuild -scheme mdview -configuration Debug -derivedDataPath build build

# Build signed release
build-release:
    rm -rf build
    xcodegen generate
    xcodebuild -scheme MarkdownViewer -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="{{sign_identity}}" build
    xcodebuild -scheme mdview -configuration Release -derivedDataPath build build
    @# Verify both products exist
    @test -d "{{build_dir}}/Release/MarkdownViewer.app" || (echo "ERROR: MarkdownViewer.app not found" && exit 1)
    @test -f "{{build_dir}}/Release/mdview" || (echo "ERROR: mdview binary not found" && exit 1)
    @# Verify signing
    codesign --verify --deep --strict "{{build_dir}}/Release/MarkdownViewer.app"
    @echo "Release build complete and signed."

# Run debug build
run: build
    killall MarkdownViewer 2>/dev/null || true
    open "{{build_dir}}/Debug/MarkdownViewer.app"

# Package release zip
package: build-release
    cd "{{build_dir}}/Release" && rm -f MarkdownViewer.zip && ditto -c -k --sequesterRsrc --keepParent MarkdownViewer.app MarkdownViewer.zip
    @echo "Packaged: {{build_dir}}/Release/MarkdownViewer.zip"
    @shasum -a 256 "{{build_dir}}/Release/MarkdownViewer.zip"

# Create GitHub release and update homebrew tap
release version: package
    @# Ensure working tree is clean
    @test -z "$(git status --porcelain)" || (echo "ERROR: uncommitted changes" && exit 1)
    @# Push source
    git push origin main
    @# Delete old release if exists
    gh release delete "v{{version}}" --repo tvaisanen/markdownviewer --yes --cleanup-tag 2>/dev/null || true
    @# Create release
    gh release create "v{{version}}" \
        "{{build_dir}}/Release/MarkdownViewer.zip" \
        "{{build_dir}}/Release/mdview" \
        --target main \
        --title "v{{version}}"
    @# Update homebrew tap
    #!/usr/bin/env bash
    set -euo pipefail
    SHA=$(shasum -a 256 "{{build_dir}}/Release/MarkdownViewer.zip" | cut -d' ' -f1)
    cd "{{tap_repo}}"
    sed -i '' "s/version \".*\"/version \"{{version}}\"/" Casks/mdview.rb
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA}\"/" Casks/mdview.rb
    git add -A
    git commit -m "Update mdview to v{{version}}"
    git push origin main
    @echo "Released v{{version}} — run: brew update && brew reinstall --cask mdview"

# Verify installed app matches latest release
verify:
    @echo "Installed app:"
    @codesign -dv /Applications/MarkdownViewer.app 2>&1 | grep -E "Identifier|TeamIdentifier"
    @echo "---"
    @echo "CLI:"
    @which mdview && mdview --version
    @echo "---"
    @echo "Release:"
    @gh release view --repo tvaisanen/markdownviewer --json tagName,createdAt --jq '"tag: \(.tagName), created: \(.createdAt)"'

# Clean all build artifacts
clean:
    rm -rf build
