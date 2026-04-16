import Cocoa

final class SidebarFileCell: NSTableCellView {

    private let filenameField = NSTextField(labelWithString: "")
    private let dirField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setup() {
        filenameField.font = .systemFont(ofSize: 13)
        filenameField.lineBreakMode = .byTruncatingTail

        dirField.font = .systemFont(ofSize: 10)
        dirField.textColor = .secondaryLabelColor
        dirField.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(filenameField)
        textStack.addArrangedSubview(dirField)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        closeButton.bezelStyle = .smallSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 3
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isHidden = true

        addSubview(textStack)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textStack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(filename: String, directory: String) {
        filenameField.stringValue = filename
        dirField.stringValue = directory
    }

    @objc private func closeClicked() {
        onClose?()
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }
}
