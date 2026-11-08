import AppKit
import SwiftUI

/// Keep both hosts alive; AppKit animates the divider and remembers its dragged width.
struct CollapsiblePane<Pane: View, Content: View>: NSViewControllerRepresentable {
    enum Kind { case navigation, inspector }
    @Binding var isVisible: Bool
    let kind: Kind
    let pane: Pane
    let content: Content

    @Environment(\.self) private var environment
    func makeCoordinator() -> Coordinator { Coordinator(self, environment: environment) }
    func makeNSViewController(context: Context) -> NSSplitViewController { context.coordinator.controller }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }

    // AppKit owns column minimums. SwiftUI must not promote the split's fitting width
    // into an outer minimum that outranks native divider dragging.
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSSplitViewController, context: Context)
        -> CGSize?
    {
        let size = proposal.replacingUnspecifiedDimensions(
            by: NSSize(width: kind == .navigation ? 1380 : 1169, height: 800))
        return size.width.isFinite && size.height.isFinite ? size : nil
    }

    final class Coordinator {
        let controller = NSSplitViewController()
        private let paneHost: PaneHost<HostedPane<Pane>>
        private let contentHost: PaneHost<HostedPane<Content>>
        private let item: NSSplitViewItem
        private var parent: CollapsiblePane
        private var observation: NSKeyValueObservation?
        private var updating = false

        init(_ parent: CollapsiblePane, environment: EnvironmentValues) {
            self.parent = parent
            paneHost = PaneHost(rootView: HostedPane(root: parent.pane, environment: environment))
            contentHost = PaneHost(rootView: HostedPane(root: parent.content, environment: environment))
            let navigation = parent.kind == .navigation
            // A shared toolbar must not track the sidebar divider. Its toggle stays
            // beside the window controls even when this custom pane changes width.
            item = NSSplitViewItem(viewController: paneHost)
            item.canCollapse = true
            item.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
            item.minimumThickness = navigation ? 180 : 210
            item.maximumThickness = navigation ? 350 : NSSplitViewItem.unspecifiedDimension
            item.canCollapseFromWindowResize = false
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            item.holdingPriority = .init(260)
            item.isCollapsed = !parent.isVisible
            let main = NSSplitViewItem(viewController: contentHost)
            main.minimumThickness = navigation ? 480 : 430
            controller.splitView.isVertical = true
            controller.splitView.dividerStyle = .thin
            controller.view.setFrameSize(NSSize(width: navigation ? 1380 : 1169, height: 800))
            paneHost.view.setFrameSize(NSSize(width: navigation ? 210 : 250, height: 800))
            contentHost.view.setFrameSize(NSSize(width: navigation ? 1169 : 918, height: 800))
            controller.splitViewItems = navigation ? [item, main] : [main, item]
            controller.splitView.autosaveName = navigation ? "DiskAtlas.navigation" : "DiskAtlas.inspector"
            observation = item.observe(\.isCollapsed) { [weak self] _, _ in self?.changedFromDrag() }
        }

        func update(_ parent: CollapsiblePane, environment: EnvironmentValues) {
            self.parent = parent
            paneHost.rootView = HostedPane(root: parent.pane, environment: environment)
            contentHost.rootView = HostedPane(root: parent.content, environment: environment)
            guard item.isCollapsed == parent.isVisible else { return }
            updating = true
            if !environment.accessibilityReduceMotion && controller.view.window != nil {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    item.animator().isCollapsed = !parent.isVisible
                }
            } else {
                item.isCollapsed = !parent.isVisible
            }
            updating = false
        }

        private func changedFromDrag() {
            guard !updating else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let visible = !item.isCollapsed
                if parent.isVisible != visible { parent.isVisible = visible }
            }
        }
    }
}

private struct HostedPane<Root: View>: View {
    let root: Root
    let environment: EnvironmentValues
    var body: some View { root.environment(\.self, environment).foregroundStyle(Palette.ink).tint(Palette.accent) }
}

/// Split items own the viewport; edge constraints keep SwiftUI tied to its actual size.
private final class PaneHost<Root: View>: NSViewController {
    private let host: NSHostingController<Root>
    var rootView: Root {
        get { host.rootView }
        set { host.rootView = newValue }
    }
    init(rootView: Root) {
        host = NSHostingController(rootView: rootView)
        host.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func loadView() {
        view = NSView()
        addChild(host)
        let hosted = host.view
        hosted.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: view.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
