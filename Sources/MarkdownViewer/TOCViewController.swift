import Cocoa
import MarkdownViewerKit

@MainActor
protocol TOCDelegate: AnyObject {
    func tocDidSelectHeading(_ heading: Heading)
}

final class TOCViewController: NSViewController {

    weak var delegate: TOCDelegate?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var headings: [Heading] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TOCColumn"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.style = .sourceList

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func updateHeadings(_ newHeadings: [Heading]) {
        headings = newHeadings
        tableView.reloadData()
    }
}

extension TOCViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        headings.count
    }
}

extension TOCViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TOCCell")
        let cellView: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cellView = existing
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 12)
            textField.lineBreakMode = .byTruncatingTail
            textField.tag = 100
            textField.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
            ])
        }

        let heading = headings[row]
        if let textField = cellView.viewWithTag(100) as? NSTextField {
            textField.stringValue = heading.text
            // Indent by heading level: h1 = 8pt, h2 = 24pt, h3 = 40pt, etc.
            let indent = CGFloat(8 + (heading.level - 1) * 16)

            // Remove old leading constraint and add new one
            textField.constraints.forEach { c in
                if c.firstAttribute == .leading { c.isActive = false }
            }
            // Find and remove superview constraints for leading
            cellView.constraints.forEach { c in
                if c.firstAttribute == .leading && (c.firstItem === textField || c.secondItem === textField) {
                    c.isActive = false
                }
            }
            let leadingConstraint = textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: indent)
            leadingConstraint.isActive = true

            // Bold for h1, regular for others
            textField.font = heading.level == 1
                ? .boldSystemFont(ofSize: 12)
                : .systemFont(ofSize: 12)
        }

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.tocDidSelectHeading(headings[row])
        // Deselect after action (like a button, not persistent selection)
        tableView.deselectRow(row)
    }
}
