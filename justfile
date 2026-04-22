sign_identity := "Developer ID Application: Toni Väisänen (42JQ8WHJ28)"
tap_repo := env("HOME") / "projects/homebrew-tap"
build_dir := "build/Build/Products"

# Build debug app and CLI
build:
    xcodegen generate
    xcodebuild -scheme MarkdownViewer -configuration Debug -derivedDataPath build build
    xcodebuild -scheme mdview -configuration Debug -derivedDataPath build build

# Build signed release (run `just trust-signing-key` once to avoid password prompts)
build-release:
    #!/usr/bin/env bash
    set -euo pipefail
    # Build unsigned, then one deep codesign pass on the .app and one on the CLI.
    rm -rf build
    xcodegen generate
    xcodebuild -scheme MarkdownViewer -configuration Release -derivedDataPath build \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
    xcodebuild -scheme mdview -configuration Release -derivedDataPath build \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
    test -d "{{build_dir}}/Release/MarkdownViewer.app" || { echo "ERROR: MarkdownViewer.app not found"; exit 1; }
    test -f "{{build_dir}}/Release/mdview" || { echo "ERROR: mdview binary not found"; exit 1; }
    # Deep sign the app (descends into embedded frameworks). --options runtime
    # enables the Hardened Runtime, required for notarization.
    codesign --force --deep --timestamp --options runtime \
        --sign "{{sign_identity}}" "{{build_dir}}/Release/MarkdownViewer.app"
    codesign --force --timestamp --options runtime \
        --sign "{{sign_identity}}" "{{build_dir}}/Release/mdview"
    codesign --verify --deep --strict "{{build_dir}}/Release/MarkdownViewer.app"
    codesign --verify --strict "{{build_dir}}/Release/mdview"
    echo "Release build complete and signed."

# Run debug build, optionally opening one or more files
run *files: build
    #!/usr/bin/env bash
    set -euo pipefail
    killall MarkdownViewer 2>/dev/null || true
    APP="$(pwd)/{{build_dir}}/Debug/MarkdownViewer.app"
    # Register the fresh bundle so LaunchServices resolves -a <path> reliably.
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREG" -f "$APP" >/dev/null 2>&1 || true
    if [ -z "{{files}}" ]; then
        open "$APP"
    else
        open -a "$APP" {{files}}
    fi

# Package release zip
package: build-release
    cd "{{build_dir}}/Release" && rm -f MarkdownViewer.zip && ditto -c -k --sequesterRsrc --keepParent MarkdownViewer.app MarkdownViewer.zip
    @echo "Packaged: {{build_dir}}/Release/MarkdownViewer.zip"
    @shasum -a 256 "{{build_dir}}/Release/MarkdownViewer.zip"

# Create GitHub release and update homebrew tap (uses one bash shell)
release version: package
    #!/usr/bin/env bash
    set -euo pipefail

    # Ensure working tree is clean
    if [ -n "$(git status --porcelain)" ]; then
        echo "ERROR: uncommitted changes"
        exit 1
    fi

    # Push source
    git push origin main

    # Delete old release (idempotent for re-runs after a mid-failure)
    gh release delete "v{{version}}" --repo tvaisanen/markdownviewer --yes --cleanup-tag 2>/dev/null || true

    # Create release
    gh release create "v{{version}}" \
        "{{build_dir}}/Release/MarkdownViewer.zip" \
        "{{build_dir}}/Release/mdview" \
        --target main \
        --title "v{{version}}"

    # Update homebrew tap
    SHA=$(shasum -a 256 "{{build_dir}}/Release/MarkdownViewer.zip" | cut -d' ' -f1)
    cd "{{tap_repo}}"
    sed -i '' "s/version \".*\"/version \"{{version}}\"/" Casks/mdview.rb
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA}\"/" Casks/mdview.rb
    git add -A
    git commit -m "Update mdview to v{{version}}"
    git push origin main

    echo "Released v{{version}} — run: brew update && brew reinstall --cask mdview"

# Grant codesign unprompted access to the signing key (run once; asks for keychain password)
trust-signing-key:
    @echo "This will update the ACL on your Developer ID signing key so codesign"
    @echo "can use it without prompting. You will be asked for your login keychain"
    @echo "password ONCE."
    @echo ""
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        ~/Library/Keychains/login.keychain-db
    @echo ""
    @echo "Done. Future releases should no longer prompt per codesign invocation."

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
