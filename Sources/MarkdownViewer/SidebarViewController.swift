import Cocoa

@MainActor
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
        let openButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Open file")!,
            target: self,
            action: #selector(openFileClicked(_:))
        )
        openButton.bezelStyle = .accessoryBarAction
        openButton.isBordered = false
        openButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(openButton)
        NSLayoutConstraint.activate([
            openButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            openButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            openButton.widthAnchor.constraint(equalToConstant: 24),
            openButton.heightAnchor.constraint(equalToConstant: 24),
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
        let cellView: SidebarFileCell

        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? SidebarFileCell {
            cellView = existing
        } else {
            cellView = SidebarFileCell()
            cellView.identifier = identifier
        }

        let item = items[row]
        cellView.configure(filename: item.filename, directory: item.parentDirectory)
        cellView.onClose = { [weak self] in
            self?.delegate?.sidebarDidRequestCloseFile(at: row)
        }

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectFile(at: row)
    }
}
