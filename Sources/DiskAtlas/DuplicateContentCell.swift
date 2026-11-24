import AppKit
import AtlasCore

/// Native labels and controls avoid inserting SwiftUI layout transactions into outline animation.
final class DuplicateContentCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let path = NSTextField(wrappingLabelWithString: "")
    let keeper = NSTextField(labelWithString: "")
    private let keeperMark = NSImageView()
    let icon = NSImageView()
    let created = NSTextField(labelWithString: "")
    let modified = NSTextField(labelWithString: "")
    let copies = NSTextField(labelWithString: "")
    let bytes = NSTextField(labelWithString: "")
    let eye = NSButton()
    let finder = NSButton()
    let trash = NSButton()
    /// Replaces only this group's selection: this copy remains, every other copy becomes a Trash candidate.
    /// It shares one fixed slot with the “Will remain” status, so rows never change height or name width.
    /// The status is a tinted capsule with a check; the command is an underlined text action without a surface.
    let keep = RowLinkButton()
    var selectAction: (() -> Void)?
    var previewAction: (() -> Void)?
    var revealAction: (() -> Void)?
    var trashAction: (() -> Void)?
    var keepAction: (() -> Void)?
    private var columns = DuplicateTableColumns()
    private var item: DuplicateOutlineItem?
    private var highlighted = false
    private var leading: CGFloat = 16
    private var trailing: CGFloat = 8
    private var remainingPill = NSRect.zero
    private static let pillFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let formatter = DateFormatter()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [name, path, keeper, created, modified, copies, bytes] { addSubview(field) }
        addSubview(icon)
        keeperMark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        addSubview(keeperMark)
        name.font = FileListMetrics.nameFont
        path.font = FileListMetrics.secondaryFont
        keeper.font = Self.pillFont
        keeper.alignment = .center
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
        keep.target = self
        keep.action = #selector(keepPressed)
        addSubview(keep)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func configure(
        _ item: DuplicateOutlineItem, columns: DuplicateTableColumns, selectedCount: Int, remaining: String?,
        fileSelected: Bool, highlighted: Bool, busy: Bool, leading: CGFloat, trailing: CGFloat
    ) {
        self.item = item
        self.columns = columns
        self.highlighted = highlighted
        self.leading = leading
        self.trailing = trailing
        configureName(item, selectedCount: selectedCount, remaining: remaining)
        configureMetadata(item)
        configureAppearance(item, selectedCount: selectedCount)
        configureActions(item, busy: busy)
        configureKeep(item, selectedCount: selectedCount, fileSelected: fileSelected, busy: busy)
        needsLayout = true
        needsDisplay = true
    }
    private func configureName(_ item: DuplicateOutlineItem, selectedCount: Int, remaining: String?) {
        let file = item.file
        name.stringValue = file.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? item.group.displayName ?? ""
        path.stringValue = file?.path ?? groupStatus(item.group, selectedCount: selectedCount, remaining: remaining)
        path.maximumNumberOfLines = file == nil ? 1 : 0
        path.lineBreakMode = file == nil ? .byTruncatingMiddle : .byWordWrapping
        keeper.stringValue = L10n.text("Останется")
        // The one-line group status may be shortened in narrow windows; keep its full text reachable.
        toolTip = file == nil ? path.stringValue : nil
        if item.more {
            name.stringValue = L10n.text("Остальные копии доступны в экспорте.")
            path.stringValue = ""
        }
    }
    private func groupStatus(_ group: DuplicateGroup, selectedCount: Int, remaining: String?) -> String {
        if selectedCount == 0 { return (group.locations ?? []).joined(separator: " · ") }
        if selectedCount == group.files.count { return L10n.text("Все копии выбраны") }
        if let remaining { return L10n.text("Останется: ") + group.remainingPlace(remaining) }
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
        keeper.textColor = NSColor(Palette.selectedText)
        keeperMark.contentTintColor = NSColor(Palette.accent)
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
    private func configureKeep(_ item: DuplicateOutlineItem, selectedCount: Int, fileSelected: Bool, busy: Bool) {
        let copyRow = item.file != nil && !item.more
        // Only the single remaining copy shows the status; any other copy can still become the one that stays.
        let onlyRemaining = copyRow && !fileSelected && selectedCount == item.group.files.count - 1
        keeper.isHidden = !onlyRemaining
        keeperMark.isHidden = keeper.isHidden
        keep.isHidden = !copyRow || onlyRemaining
        keep.isEnabled = !busy
        keep.title = L10n.text("Оставить")
        keep.toolTip = L10n.text("Эта копия останется, остальные копии группы будут отмечены для Корзины")
        keep.setAccessibilityLabel(L10n.text("Оставить эту копию") + ": " + (item.file?.path ?? ""))
        keeper.setAccessibilityLabel(L10n.text("Останется") + ": " + (item.file?.path ?? ""))
    }
    /// One width for both states and languages' current strings keeps names from shifting between transitions.
    private static func slotWidth() -> CGFloat {
        let keep = RowLinkButton.width(L10n.text("Оставить"))
        let pill = (L10n.text("Останется") as NSString).size(withAttributes: [.font: pillFont]).width + 26
        return ceil(max(keep, pill))
    }
    override func layout() {
        super.layout()
        let dates = CGFloat((columns.created ? 1 : 0) + (columns.modified ? 1 : 0)) * FileListMetrics.dateWidth
        let nameWidth = max(
            0,
            bounds.width - leading - trailing - dates - DuplicateTableColumns.copiesWidth - FileListMetrics.sizeWidth
                - DuplicateTableColumns.actionsWidth)
        icon.frame = NSRect(x: leading, y: 9, width: 16, height: 16)
        let slot: CGFloat = item?.file == nil || item?.more == true ? 0 : Self.slotWidth()
        name.frame = NSRect(
            x: leading + 25, y: 6, width: max(0, nameWidth - 25 - 8 - (slot > 0 ? slot + 6 : 0)), height: 17)
        let slotX = leading + nameWidth - 8 - slot
        let keepWidth = min(slot, RowLinkButton.width(keep.title))
        keep.frame = NSRect(x: slotX + slot - keepWidth, y: 4, width: keepWidth, height: 20)
        let pillWidth = min(slot, ceil(keeper.attributedStringValue.size().width) + 26)
        remainingPill = NSRect(x: slotX + slot - pillWidth, y: 5, width: pillWidth, height: 18)
        keeperMark.frame = NSRect(x: remainingPill.minX + 7, y: 9, width: 9, height: 10)
        keeper.frame = NSRect(x: remainingPill.minX + 17, y: 7, width: pillWidth - 22, height: 14)
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
        // A selected copy recolors its own band, so the row shows one selection shape, never band plus inset.
        if item?.file != nil {
            (highlighted ? NSColor(Palette.mark) : NSColor(Palette.soft).withAlphaComponent(0.6)).setFill()
            bounds.fill()
        } else if highlighted {
            NSColor(Palette.mark).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        if !keeper.isHidden {
            // A translucent tint stays visible over the plain and the marked (selected) row alike.
            NSColor(Palette.accent).withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: remainingPill, xRadius: 9, yRadius: 9).fill()
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return [eye, finder, trash, keep].contains { hit === $0 || hit.isDescendant(of: $0) } ? hit : self
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
        if !keep.isHidden, keep.isEnabled {
            menu.addItem(.separator())
            let entry = NSMenuItem(
                title: L10n.text("Оставить эту копию"), action: #selector(keepPressed), keyEquivalent: "")
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
    @objc private func keepPressed() { keepAction?() }
}

/// AppKit form of the inspector's underlined text actions (“Open”): calm accent text with an underline at rest,
/// so it reads as clickable without hover yet stays secondary to the name. Hover/press add the marked surface
/// and ink text, keyboard focus the accent outline; the whole padded frame is the click target.
final class RowLinkButton: NSButton {
    static let font = NSFont.systemFont(ofSize: 11)
    /// Accent tone of the inspector links; the light value is deepened to keep 4.5:1 on the marked (selected) band.
    private static let tone = Palette.adaptive(0x315b40, 0xa6cbb0, contrastLight: 0x1f3f2a, contrastDark: 0xd6eddb)
    private var hovered = false { didSet { needsDisplay = true } }
    static func width(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font]).width) + 14
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var isHidden: Bool { didSet { if isHidden { hovered = false } } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    /// Space activates the focused action itself instead of reaching the row's Quick Look shortcut.
    override func keyDown(with event: NSEvent) {
        if isEnabled, event.charactersIgnoringModifiers == " " { performClick(nil) } else { super.keyDown(with: event) }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }
    override func draw(_ dirtyRect: NSRect) {
        let focused = isEnabled && window?.isKeyWindow == true && window?.firstResponder === self
        let active = isEnabled && (isHighlighted || hovered)
        if active {
            NSColor(Palette.mark).withAlphaComponent(isHighlighted ? 1 : 0.65).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        if focused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            ring.lineWidth = 2
            NSColor(Palette.accent).setStroke()
            ring.stroke()
        }
        let color = NSColor(!isEnabled ? Palette.sub : active || focused ? Palette.ink : Self.tone)
        let text = NSAttributedString(
            string: title,
            attributes: [.font: Self.font, .foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
