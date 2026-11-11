import AppKit
import AtlasCore

/// Native labels and controls avoid inserting SwiftUI layout transactions into outline animation.
final class DuplicateContentCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let path = NSTextField(wrappingLabelWithString: "")
    let keeper = NSTextField(labelWithString: "")
    let icon = NSImageView()
    let created = NSTextField(labelWithString: "")
    let modified = NSTextField(labelWithString: "")
    let copies = NSTextField(labelWithString: "")
    let bytes = NSTextField(labelWithString: "")
    let eye = NSButton()
    let finder = NSButton()
    let trash = NSButton()
    var selectAction: (() -> Void)?
    var previewAction: (() -> Void)?
    var revealAction: (() -> Void)?
    var trashAction: (() -> Void)?
    private var columns = DuplicateTableColumns()
    private var item: DuplicateOutlineItem?
    private var highlighted = false
    private var leading: CGFloat = 16
    private var trailing: CGFloat = 8
    private let formatter = DateFormatter()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [name, path, keeper, created, modified, copies, bytes] { addSubview(field) }
        addSubview(icon)
        name.font = FileListMetrics.nameFont
        path.font = FileListMetrics.secondaryFont
        keeper.font = FileListMetrics.secondaryFont
        for field in [created, modified] { field.font = FileListMetrics.dateFont }
        for field in [copies, bytes] {
            field.font = FileListMetrics.sizeFont
            field.alignment = .right
        }
        name.lineBreakMode = .byTruncatingMiddle
        formatter.dateStyle = .short
        for (button, symbol, action) in [
            (eye, "eye", #selector(previewPressed)), (finder, "arrow.up.forward.square", #selector(revealPressed)),
            (trash, "trash", #selector(trashPressed)),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.isBordered = false
            button.target = self
            button.action = action
            addSubview(button)
        }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func configure(
        _ item: DuplicateOutlineItem, columns: DuplicateTableColumns, selectedCount: Int, fileSelected: Bool,
        highlighted: Bool, busy: Bool, leading: CGFloat, trailing: CGFloat
    ) {
        self.item = item
        self.columns = columns
        self.highlighted = highlighted
        self.leading = leading
        self.trailing = trailing
        configureName(item, selectedCount: selectedCount, fileSelected: fileSelected)
        configureMetadata(item)
        configureAppearance(item, selectedCount: selectedCount)
        configureActions(item, busy: busy)
        needsLayout = true
        needsDisplay = true
    }
    private func configureName(_ item: DuplicateOutlineItem, selectedCount: Int, fileSelected: Bool) {
        let file = item.file
        name.stringValue = file.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? item.group.displayName ?? ""
        path.stringValue = file?.path ?? groupStatus(item.group, selectedCount: selectedCount)
        path.maximumNumberOfLines = file == nil ? 1 : 0
        path.lineBreakMode = file == nil ? .byTruncatingMiddle : .byWordWrapping
        keeper.stringValue = L10n.text("Останется")
        keeper.isHidden = file == nil || fileSelected || selectedCount == 0
        if item.more {
            name.stringValue = L10n.text("Остальные копии доступны в экспорте.")
            path.stringValue = ""
        }
    }
    private func groupStatus(_ group: DuplicateGroup, selectedCount: Int) -> String {
        if selectedCount == 0 { return (group.locations ?? []).joined(separator: " · ") }
        if selectedCount == group.files.count { return L10n.text("Все копии выбраны") }
        return L10n.text("Останется: ") + String(group.files.count - selectedCount)
    }
    private func configureMetadata(_ item: DuplicateOutlineItem) {
        let file = item.file
        formatter.locale = Locale(identifier: L10n.language == "en" ? "en_US" : "ru_RU")
        created.stringValue =
            file.flatMap { $0.created.timeIntervalSince1970 == 0 ? nil : $0.created }.map(formatter.string) ?? "—"
        modified.stringValue = file.map { formatter.string(from: $0.modified) } ?? "—"
        copies.stringValue = file == nil ? item.group.files.count.formatted() : ""
        bytes.stringValue = byteString(file?.bytes ?? item.group.repeatedBytes)
    }
    private func configureAppearance(_ item: DuplicateOutlineItem, selectedCount: Int) {
        let kind = FileKind.classify(URL(fileURLWithPath: item.file?.path ?? item.group.files.first?.path ?? ""))
        icon.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
        icon.contentTintColor = NSColor(kind.tint)
        name.textColor = NSColor(Palette.ink)
        for field in [path, created, modified] { field.textColor = NSColor(Palette.sub) }
        keeper.textColor = NSColor(Palette.accent)
        if item.file == nil && selectedCount > 0 {
            path.textColor = selectedCount == item.group.files.count ? .systemOrange : NSColor(Palette.accent)
        }
        for field in [copies, bytes] { field.textColor = NSColor(Palette.ink) }
        for button in [eye, finder, trash] { button.contentTintColor = NSColor(Palette.ink) }
        icon.isHidden = item.more
        created.isHidden = item.more || !columns.created
        modified.isHidden = item.more || !columns.modified
        copies.isHidden = item.more
        bytes.isHidden = item.more
    }
    private func configureActions(_ item: DuplicateOutlineItem, busy: Bool) {
        eye.isHidden = item.file == nil || item.more
        finder.isHidden = eye.isHidden
        trash.isHidden = item.more
        trash.isEnabled = !busy
        eye.toolTip = L10n.text("Быстрый просмотр · Пробел")
        finder.toolTip = L10n.text("Показать в Finder")
        trash.toolTip = L10n.text("В корзину…")
        eye.setAccessibilityLabel(L10n.text("Быстрый просмотр") + ": " + name.stringValue)
        finder.setAccessibilityLabel(L10n.text("Показать в Finder"))
        trash.setAccessibilityLabel(L10n.text("В корзину") + ": " + name.stringValue)
    }
    override func layout() {
        super.layout()
        let dates = CGFloat((columns.created ? 1 : 0) + (columns.modified ? 1 : 0)) * FileListMetrics.dateWidth
        let nameWidth = max(
            0,
            bounds.width - leading - trailing - dates - DuplicateTableColumns.copiesWidth - FileListMetrics.sizeWidth
                - DuplicateTableColumns.actionsWidth)
        icon.frame = NSRect(x: leading, y: 9, width: 16, height: 16)
        let badge: CGFloat = keeper.isHidden ? 0 : 58
        name.frame = NSRect(x: leading + 25, y: 6, width: max(0, nameWidth - 25 - 8 - badge), height: 17)
        keeper.frame = NSRect(x: leading + nameWidth - 8 - badge, y: 8, width: badge, height: 14)
        path.frame = NSRect(
            x: leading + 25, y: 24, width: max(0, nameWidth - 25 - 8), height: max(0, bounds.height - 27))
        var x = leading + nameWidth
        for (field, visible) in [(created, columns.created), (modified, columns.modified)] where visible {
            field.frame = NSRect(x: x + 6, y: 9, width: FileListMetrics.dateWidth - 12, height: 17)
            x += FileListMetrics.dateWidth
        }
        copies.frame = NSRect(x: x, y: 9, width: DuplicateTableColumns.copiesWidth, height: 17)
        x += DuplicateTableColumns.copiesWidth
        bytes.frame = NSRect(x: x + 6, y: 9, width: FileListMetrics.sizeWidth - 12, height: 17)
        x += FileListMetrics.sizeWidth
        for (offset, button) in [eye, finder, trash].enumerated() {
            button.frame = NSRect(x: x + CGFloat(offset * 32), y: 4, width: 24, height: 28)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if item?.file != nil {
            NSColor(Palette.soft).withAlphaComponent(0.6).setFill()
            bounds.fill()
        }
        if highlighted {
            NSColor(Palette.mark).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return [eye, finder, trash].contains { hit === $0 || hit.isDescendant(of: $0) } ? hit : self
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard item?.file != nil else { return nil }
        let menu = NSMenu()
        for (title, action) in [
            ("Быстрый просмотр", #selector(previewPressed)), ("Показать в Finder", #selector(revealPressed)),
            ("Скопировать путь", #selector(copyPath)),
        ] {
            let entry = NSMenuItem(title: L10n.text(title), action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        return menu
    }
    @objc private func copyPath() {
        guard let path = item?.file?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2, item?.file != nil { revealAction?() } else { selectAction?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.isQuickLookKey { if !event.isARepeat { previewPressed() } } else { super.keyDown(with: event) }
    }
    @objc private func previewPressed() {
        window?.makeFirstResponder(self)
        previewAction?()
    }
    @objc private func revealPressed() { revealAction?() }
    @objc private func trashPressed() { trashAction?() }
}
