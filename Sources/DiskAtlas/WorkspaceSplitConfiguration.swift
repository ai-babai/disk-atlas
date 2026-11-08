import AppKit
import SwiftUI

/// SwiftUI owns the split's layout; AppKit persists only the user's divider position.
struct WorkspaceSplitConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SplitProbe() }
    func updateNSView(_ view: NSView, context: Context) {}
}
private final class SplitProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        var parent = superview
        while let view = parent {
            if let split = view as? NSSplitView, !split.isVertical {
                split.autosaveName = "atlas.workspace.map-list"
                return
            }
            parent = view.superview
        }
    }
}
