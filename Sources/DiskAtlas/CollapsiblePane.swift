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

    final class Coordinator {
        let controller = NSSplitViewController()
        private let paneHost: NSHostingController<HostedPane<Pane>>
        private let contentHost: NSHostingController<HostedPane<Content>>
        private let item: NSSplitViewItem
        private var parent: CollapsiblePane
        private var observation: NSKeyValueObservation?
        private var updating = false

        init(_ parent: CollapsiblePane, environment: EnvironmentValues) {
            self.parent = parent
            paneHost = NSHostingController(rootView: HostedPane(root: parent.pane, environment: environment))
            contentHost = NSHostingController(rootView: HostedPane(root: parent.content, environment: environment))
            paneHost.sizingOptions = []
            contentHost.sizingOptions = []
            let navigation = parent.kind == .navigation
            item =
                navigation
                ? NSSplitViewItem(sidebarWithViewController: paneHost)
                : NSSplitViewItem(inspectorWithViewController: paneHost)
            item.minimumThickness = navigation ? 180 : 210
            item.maximumThickness = navigation ? 350 : 380
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
