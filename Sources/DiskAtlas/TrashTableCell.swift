import AppKit

/// Fixed columns keep checkbox and per-row Trash actions independent of row focus.
final class TrashTableCell: NSTableCellView {
    let button: NSButton
    var action: (() -> Void)?
    init(checkbox: Bool) {
        button = checkbox ? NSButton(checkboxWithTitle: "", target: nil, action: nil) : NSButton()
        super.init(frame: .zero)
        if !checkbox {
            button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            button.isBordered = false
            button.imagePosition = .imageOnly
        }
        button.target = self
        button.action = #selector(pressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor), button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func pressed() { action?() }
}
