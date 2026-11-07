import AppKit
import SwiftUI

extension NSEvent {
    var isQuickLookKey: Bool {
        keyCode == 49 && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

/// A local key responder for a copy's label; never intercepts search fields or checkboxes.
struct PreviewKeyboard: NSViewRepresentable {
    let active: Bool
    let preview: () -> Void
    let blurred: () -> Void

    func makeNSView(context: Context) -> PreviewKeyView { PreviewKeyView() }
    func updateNSView(_ view: PreviewKeyView, context: Context) {
        view.preview = preview
        view.blurred = blurred
        if active, let window = view.window, window.isKeyWindow, window.firstResponder !== view {
            window.makeFirstResponder(view)
        }
    }
}

final class PreviewKeyView: NSView {
    var preview: (() -> Void)?
    var blurred: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { DispatchQueue.main.async { [weak self] in self?.blurred?() } }
        return result
    }
    override func keyDown(with event: NSEvent) {
        if event.isQuickLookKey {
            if !event.isARepeat { preview?() }
        } else if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
