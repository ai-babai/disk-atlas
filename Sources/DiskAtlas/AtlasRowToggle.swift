import AppKit
import SwiftUI

/// The same AppKit checkbox and disclosure styles used by the native file outline.
struct AtlasRowToggle: NSViewRepresentable {
    let state: NSControl.StateValue
    var disclosure = false
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> RowToggleHost { RowToggleHost(disclosure: disclosure) }
    func updateNSView(_ view: RowToggleHost, context: Context) {
        view.action = action
        view.button.state = state
        view.button.isEnabled = enabled
        view.button.allowsMixedState = state == .mixed
        view.button.setAccessibilityLabel(label)
        view.button.toolTip = label
    }
}

final class RowToggleHost: NSView {
    let button: NSButton
    var action: (() -> Void)?
    init(disclosure: Bool) {
        button = disclosure ? NSButton() : NSButton(checkboxWithTitle: "", target: nil, action: nil)
        super.init(frame: .zero)
        if disclosure {
            button.title = ""
            button.bezelStyle = .disclosure
            button.setButtonType(.pushOnPushOff)
            button.setAccessibilityRole(.disclosureTriangle)
        }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(pressed)
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }
    override func layout() {
        super.layout()
        button.frame = bounds
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func pressed() { action?() }
}
