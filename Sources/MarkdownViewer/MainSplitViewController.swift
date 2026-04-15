import Cocoa

final class MainSplitViewController: NSSplitViewController {

    let sidebarViewController = SidebarViewController()
    let contentViewController = ContentViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 300
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings

        let contentItem = NSSplitViewItem(viewController: contentViewController)
        contentItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }
}
