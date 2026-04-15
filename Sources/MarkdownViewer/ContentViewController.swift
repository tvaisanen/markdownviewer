import Cocoa
import MarkdownViewerKit

final class ContentViewController: NSViewController {

    let webContentView = WebContentView(frame: .zero)
    private let emptyStateLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebContentView()
        setupEmptyState()
        showEmptyState()
    }

    private func setupWebContentView() {
        webContentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webContentView)
        NSLayoutConstraint.activate([
            webContentView.topAnchor.constraint(equalTo: view.topAnchor),
            webContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyStateLabel.stringValue = "Open a file to get started\n⌘O"
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 16)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func showEmptyState() {
        webContentView.isHidden = true
        emptyStateLabel.isHidden = false
    }

    func showContent() {
        webContentView.isHidden = false
        emptyStateLabel.isHidden = true
    }
}
