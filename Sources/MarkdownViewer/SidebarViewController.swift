import Cocoa

protocol SidebarDelegate: AnyObject {
    func sidebarDidSelectFile(at index: Int)
    func sidebarDidRequestCloseFile(at index: Int)
    func sidebarDidRequestOpenFile()
}

final class SidebarViewController: NSViewController {

    weak var delegate: SidebarDelegate?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    struct FileItem {
        let filename: String
        let parentDirectory: String
    }

    private var items: [FileItem] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupOpenButton()
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 44
        tableView.style = .sourceList

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -36),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let menu = NSMenu()
        menu.addItem(withTitle: "Close", action: #selector(closeSelectedFile(_:)), keyEquivalent: "")
        tableView.menu = menu
    }

    private func setupOpenButton() {
        let button = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Open file")!,
            target: self,
            action: #selector(openFileClicked(_:))
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func updateFiles(_ files: [FileItem]) {
        items = files
        tableView.reloadData()
    }

    func selectRow(_ index: Int) {
        guard index >= 0 && index < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    @objc private func openFileClicked(_ sender: Any?) {
        delegate?.sidebarDidRequestOpenFile()
    }

    @objc private func closeSelectedFile(_ sender: Any?) {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidRequestCloseFile(at: row)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            let row = tableView.selectedRow
            guard row >= 0 else { return }
            delegate?.sidebarDidRequestCloseFile(at: row)
        } else {
            super.keyDown(with: event)
        }
    }
}

extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

extension SidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cellView: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cellView = existing
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let stackView = NSStackView()
            stackView.orientation = .vertical
            stackView.alignment = .leading
            stackView.spacing = 1
            stackView.translatesAutoresizingMaskIntoConstraints = false

            let filenameField = NSTextField(labelWithString: "")
            filenameField.font = .systemFont(ofSize: 13)
            filenameField.lineBreakMode = .byTruncatingTail
            filenameField.tag = 100

            let dirField = NSTextField(labelWithString: "")
            dirField.font = .systemFont(ofSize: 10)
            dirField.textColor = .secondaryLabelColor
            dirField.lineBreakMode = .byTruncatingMiddle
            dirField.tag = 200

            stackView.addArrangedSubview(filenameField)
            stackView.addArrangedSubview(dirField)

            cellView.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                stackView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                stackView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        let item = items[row]
        if let filenameField = cellView.viewWithTag(100) as? NSTextField {
            filenameField.stringValue = item.filename
        }
        if let dirField = cellView.viewWithTag(200) as? NSTextField {
            dirField.stringValue = item.parentDirectory
        }

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectFile(at: row)
    }
}
