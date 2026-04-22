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
    private let fileWatcher = FileWatcher()

    private let themePopup = NSPopUpButton()
    private let paperPopup = NSPopUpButton()
    private let orientationPopup = NSPopUpButton()
    private let startPageAtH1Checkbox = NSButton(checkboxWithTitle: "Start page at H1", target: nil, action: nil)
    private let headerCheckbox = NSButton(checkboxWithTitle: "Header", target: nil, action: nil)
    private let footerCheckbox = NSButton(checkboxWithTitle: "Footer", target: nil, action: nil)
    private let headerField = NSTextField(string: "")
    private let exportButton = NSButton(title: "Export…", target: nil, action: nil)
    private let printButton = NSButton(title: "Print…", target: nil, action: nil)

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

        seedPaperSizeFromLocale()
        setupLayout()
        regenerate()

        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in self?.regenerate() }
        }
        fileWatcher.watch(path: sourceURL.path)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        fileWatcher.stop()
    }

    // MARK: - Layout

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
            NSView(),
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

    // MARK: - Actions

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let t = PDFTheme(rawValue: raw) else { return }
        currentOptions.theme = t
        applyThemeDefaultsForCurrentTheme()
        ThemeManager.shared.current = t
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

    // MARK: - Helpers

    /// Reset header/footer chrome defaults when the theme changes. (User edits after
    /// a theme switch are preserved until the next switch.)
    private func applyThemeDefaultsForCurrentTheme() {
        currentOptions.showHeader = currentOptions.theme.defaultShowHeader
        currentOptions.showFooter = currentOptions.theme.defaultShowFooter
        headerCheckbox.state = currentOptions.showHeader ? .on : .off
        footerCheckbox.state = currentOptions.showFooter ? .on : .off
    }

    /// Initialize paper size from the system default (Letter in US, A4 elsewhere).
    private func seedPaperSizeFromLocale() {
        let sys = NSPrintInfo.shared.paperSize
        let a4Height: CGFloat = 842
        currentOptions.paperSize = (abs(sys.height - a4Height) < abs(sys.height - 792)) ? .a4 : .letter
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
