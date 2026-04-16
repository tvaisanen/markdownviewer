import Cocoa

final class MainSplitViewController: NSSplitViewController {

    let sidebarViewController = SidebarViewController()
    let contentViewController = ContentViewController()
    let tocViewController = TOCViewController()

    enum SidebarMode {
        case files
        case toc
    }

    private(set) var currentMode: SidebarMode = .files

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(viewController: sidebarViewController)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 300

        let contentItem = NSSplitViewItem(viewController: contentViewController)
        contentItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        sidebarItem.isCollapsed = true
    }

    func switchSidebar(to mode: SidebarMode) {
        guard mode != currentMode else { return }
        currentMode = mode

        let sidebarItem = splitViewItems[0]
        let newController: NSViewController = (mode == .files) ? sidebarViewController : tocViewController

        removeSplitViewItem(sidebarItem)

        let newSidebarItem = NSSplitViewItem(viewController: newController)
        newSidebarItem.canCollapse = true
        newSidebarItem.minimumThickness = 180
        newSidebarItem.maximumThickness = 300

        insertSplitViewItem(newSidebarItem, at: 0)
    }
}
