import AppKit
import AtlasCore
import SwiftUI

/// Native, virtualized rows with the app palette. Selection does not rebuild cells.
struct FileTable: NSViewRepresentable {
    var rows: [Entry]
    var logical: Bool
    var folderBytes: Int64
    var revision: Int
    var language: String
    var showPaths: Bool
    var contextID: Int? = nil
    var showCreationDate: Bool
    var sort: EntrySort = .size
    var descending = true
    var sortBy: (EntrySort) -> Void = { _ in }
    var duplicates: DuplicateLookup? = nil
    var showDuplicates: (String) -> Void = { _ in }
    var scrollRequest = 0
    @Binding var selection: Int?
    var open: (Int) -> Void
    var reveal: (Entry) -> Void
    var copyPath: (String) -> Void
    var preview: (Entry) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = AtlasTableScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = AtlasTableView()
        table.headerView = AtlasHeaderView(frame: NSRect(x: 0, y: 0, width: 500, height: 28))
        table.allowsColumnResizing = false
        table.allowsColumnReordering = false
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openRow)
        table.returnAction = { [weak coordinator = context.coordinator] in coordinator?.openRow() }
        table.previewAction = { [weak coordinator = context.coordinator] in coordinator?.previewRow() }
        for (name, width) in [("name", 260.0), ("created", 92.0), ("modified", 92.0), ("size", 100.0), ("share", 65.0)]
        {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = width
            column.minWidth = name == "name" ? 80 : width
            column.resizingMask = name == "name" ? .autoresizingMask : []
            let header = AtlasHeaderCell(textCell: name)
            header.press = { [weak coordinator = context.coordinator] in
                guard let field = EntrySort(rawValue: name) else { return }
                coordinator?.parent.sortBy(field)
            }
            column.sortDescriptorPrototype = NSSortDescriptor(key: name, ascending: name == "name")
            column.headerCell = header
            table.addTableColumn(column)
        }
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        scroll.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        table.backgroundColor = NSColor(Palette.paper)
        table.rowHeight = showPaths ? 43 : 33
        let titles = [
            "name": "Имя", "created": "Создан", "modified": "Изменён", "size": logical ? "Размер" : "На диске",
            "share": "Доля",
        ]
        for column in table.tableColumns {
            let key = column.identifier.rawValue
            column.headerCell.stringValue =
                L10n.text(titles[key] ?? key) + (key == sort.rawValue ? descending ? " ↓" : " ↑" : "")
            column.headerCell.font = .systemFont(ofSize: 10, weight: .medium)
            column.headerCell.alignment = key == "size" || key == "share" ? .right : .left
            if let header = column.headerCell as? AtlasHeaderCell { header.color = NSColor(Palette.sub) }
        }
        table.headerView?.needsDisplay = true
        table.tableColumns.first { $0.identifier.rawValue == "created" }?.isHidden = !showCreationDate
        scroll.needsLayout = true
        coordinator.reloadIfNeeded()
        coordinator.updateSelection()
        coordinator.scrollSelection(animated: !reduceMotion)
        table.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FileTable
        weak var table: NSTableView?
        var duplicateID: UUID?
        var revision = -1
        var scrollRequest = 0
        var language = ""
        var logical = false
        var showPaths = false
        var suppressSelection = false
        let dateFormatter = DateFormatter()
        init(_ parent: FileTable) { self.parent = parent }
        func reloadIfNeeded() {
            guard let table else { return }
            guard
                revision != parent.revision || language != parent.language || logical != parent.logical
                    || showPaths != parent.showPaths || duplicateID != parent.duplicates?.id
            else { return }
            duplicateID = parent.duplicates?.id
            revision = parent.revision
            language = parent.language
            dateFormatter.locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
            dateFormatter.dateStyle = .short
            logical = parent.logical
            showPaths = parent.showPaths
            suppressSelection = true
            table.reloadData()
            suppressSelection = false
        }
        func updateSelection() {
            guard let table else { return }
            let desired = parent.selection.flatMap { id in parent.rows.firstIndex { $0.id == id } } ?? -1
            if desired != table.selectedRow {
                suppressSelection = true
                table.selectRowIndexes(desired < 0 ? [] : IndexSet(integer: desired), byExtendingSelection: false)
                suppressSelection = false
            }
        }
        func scrollSelection(animated: Bool) {
            let request = parent.scrollRequest
            guard request > 0, scrollRequest != request else { return }
            DispatchQueue.main.async { [weak self] in self?.performScroll(request, animated: animated) }
        }
        private func performScroll(_ request: Int, animated: Bool) {
            guard parent.scrollRequest == request, let table, let selection = parent.selection,
                let row = parent.rows.firstIndex(where: { $0.id == selection }), let scroll = table.enclosingScrollView
            else { return }
            scroll.layoutSubtreeIfNeeded()
            scrollRequest = request
            let clip = scroll.contentView
            let origin = clip.bounds.origin
            table.scrollRowToVisible(row)
            let destination = clip.bounds.origin
            guard animated, origin != destination else { return }
            clip.scroll(to: origin)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                clip.animator().setBoundsOrigin(destination)
            } completionHandler: {
                scroll.reflectScrolledClipView(clip)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            parent.showPaths || parent.rows[row].id == parent.contextID ? 43 : 33
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let key = tableView.sortDescriptors.first?.key, let field = EntrySort(rawValue: key) {
                parent.sortBy(field)
            }
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { AtlasRowView() }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelection, let table else { return }
            let row = table.selectedRow
            parent.selection = row >= 0 && row < parent.rows.count ? parent.rows[row].id : nil
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count, let key = tableColumn?.identifier else { return nil }
            let entry = parent.rows[row]
            let cell =
                (tableView.makeView(withIdentifier: key, owner: self) as? AtlasCell) ?? AtlasCell(identifier: key)
            let bytes = parent.logical ? entry.logicalBytes : entry.bytes
            switch key.rawValue {
            case "name":
                cell.title.stringValue = entry.name
                cell.subtitle.stringValue = parent.showPaths || entry.id == parent.contextID ? entry.path : ""
                cell.icon.image = NSImage(systemSymbolName: entry.kind.symbol, accessibilityDescription: nil)
                cell.icon.contentTintColor = NSColor(entry.kind.tint)
                cell.toolTip = entry.path
                let groupID = parent.duplicates?.byPath[entry.path]
                cell.duplicateButton.isHidden = groupID == nil
                cell.duplicateAction = { [weak self] in self?.parent.showDuplicates(entry.path) }
                cell.duplicateButton.toolTip =
                    L10n.text("Показать все копии") + " · " + (parent.duplicates.map { L10n.date($0.checkedAt) } ?? "")
                cell.duplicateButton.setAccessibilityLabel(L10n.text("Дубликаты") + ": " + entry.name)
            case "size": cell.title.stringValue = byteString(bytes)
            case "created", "modified":
                let date = key.rawValue == "created" ? entry.created : entry.modified
                cell.title.stringValue = date.map { dateFormatter.string(from: $0) } ?? "—"
                cell.toolTip = date.map { L10n.date($0) } ?? L10n.text("Дата создания не сохранена в этом снимке")
            default:
                let share = Double(bytes) / Double(max(1, parent.folderBytes)) * 100
                let number = String(format: "%.1f", share)
                cell.title.stringValue =
                    (parent.language == "ru" ? number.replacingOccurrences(of: ".", with: ",") : number) + "%"
            }
            cell.setAccessibilityLabel(cell.title.stringValue)
            cell.needsLayout = true
            return cell
        }
        @objc func openRow() {
            guard let table, table.selectedRow >= 0, table.selectedRow < parent.rows.count else { return }
            parent.open(parent.rows[table.selectedRow].id)
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard row >= 0, row < parent.rows.count else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let entry = parent.rows[row]
            add(menu, L10n.text("Быстрый просмотр"), #selector(previewRow))
            if entry.isDirectory { add(menu, L10n.text("Открыть папку"), #selector(openRow)) }
            add(menu, L10n.text("Показать в Finder"), #selector(revealRow))
            add(menu, L10n.text("Скопировать путь"), #selector(copyRow))
        }
        private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        @objc private func revealRow() {
            guard let table, table.selectedRow >= 0 else { return }
            parent.reveal(parent.rows[table.selectedRow])
        }
        @objc func previewRow() {
            guard let table, table.selectedRow >= 0, table.selectedRow < parent.rows.count else { return }
            parent.preview(parent.rows[table.selectedRow])
        }
        @objc private func copyRow() {
            guard let table, table.selectedRow >= 0 else { return }
            parent.copyPath(parent.rows[table.selectedRow].path)
        }
    }
}

private final class AtlasHeaderCell: NSTableHeaderCell {
    var press: (() -> Void)?
    var color = NSColor.secondaryLabelColor
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 10), .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        (stringValue as NSString).draw(
            in: NSRect(x: cellFrame.minX, y: cellFrame.midY - 6, width: cellFrame.width, height: 15),
            withAttributes: attributes)
    }
    override func accessibilityPerformPress() -> Bool {
        press?()
        return true
    }
}

private final class AtlasHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(Palette.paper).setFill()
        dirtyRect.fill()
        guard let tableView else { return }
        for (index, column) in tableView.tableColumns.enumerated() where !column.isHidden {
            let rect = headerRect(ofColumn: index)
            let name = column.identifier.rawValue
            column.headerCell.drawInterior(
                withFrame: NSRect(
                    x: rect.minX + (name == "name" ? 12 : 4), y: rect.minY,
                    width: max(0, rect.width - (name == "name" ? 24 : 15)), height: rect.height), in: self)
        }
        NSColor(Palette.line).setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
    override func mouseDown(with event: NSEvent) {
        guard let tableView else { return }
        let column = column(at: convert(event.locationInWindow, from: nil))
        if column >= 0, column < tableView.tableColumns.count {
            (tableView.tableColumns[column].headerCell as? AtlasHeaderCell)?.press?()
        }
    }
}

private final class AtlasTableScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, let name = table.tableColumns.first else { return }
        let fixedWidth = table.tableColumns.dropFirst().filter { !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width }
        let width = max(0, contentView.bounds.width - 16)
        let nameWidth = max(name.minWidth, width - fixedWidth)
        if abs(name.width - nameWidth) > 0.5 || abs(table.frame.width - width) > 0.5 {
            name.width = nameWidth
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
            table.tile()
        }
    }
}

private final class AtlasTableView: NSTableView {
    var returnAction: (() -> Void)?
    var previewAction: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.isQuickLookKey {
            if !event.isARepeat { previewAction?() }
            return
        }
        if event.keyCode == 36 { returnAction?() } else { super.keyDown(with: event) }
    }
}

private final class AtlasRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Palette.paper).setFill()
        dirtyRect.fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor(Palette.mark).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class AtlasCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let icon = NSImageView()
    let duplicateButton = NSButton()
    var duplicateAction: (() -> Void)?
    private let isName: Bool
    private let isDate: Bool
    init(identifier: NSUserInterfaceItemIdentifier) {
        isName = identifier.rawValue == "name"
        isDate = identifier.rawValue == "created" || identifier.rawValue == "modified"
        super.init(frame: .zero)
        self.identifier = identifier
        title.font =
            isName
            ? .systemFont(ofSize: 12, weight: .medium)
            : .monospacedDigitSystemFont(ofSize: isDate ? 10 : 11, weight: .regular)
        title.textColor = NSColor(isDate ? Palette.sub : Palette.ink)
        title.lineBreakMode = .byTruncatingTail
        title.alignment = isName || isDate ? .left : .right
        subtitle.font = .systemFont(ofSize: 9)
        subtitle.textColor = NSColor(Palette.sub)
        subtitle.lineBreakMode = .byTruncatingMiddle
        addSubview(title)
        if isName {
            addSubview(icon)
            addSubview(subtitle)
            duplicateButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            duplicateButton.isBordered = false
            duplicateButton.imagePosition = .imageOnly
            duplicateButton.contentTintColor = NSColor(Palette.accent)
            duplicateButton.target = self
            duplicateButton.action = #selector(showCopies)
            duplicateButton.isHidden = true
            addSubview(duplicateButton)
        }
        textField = title
        setAccessibilityElement(true)
    }
    @objc private func showCopies() { duplicateAction?() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        if isName {
            icon.frame = NSRect(x: 9, y: (bounds.height - 16) / 2, width: 16, height: 16)
            let hasSubtitle = !subtitle.stringValue.isEmpty
            let available = max(0, bounds.width - 42 - (duplicateButton.isHidden ? 0 : 28))
            let titleWidth =
                duplicateButton.isHidden
                ? available
                : min(
                    available,
                    ceil((title.stringValue as NSString).size(withAttributes: [.font: title.font!]).width) + 8)
            title.frame = NSRect(
                x: 34, y: hasSubtitle ? bounds.height / 2 : (bounds.height - 17) / 2, width: titleWidth, height: 17)
            duplicateButton.frame = NSRect(
                x: 38 + titleWidth, y: hasSubtitle ? bounds.height / 2 - 3 : (bounds.height - 24) / 2, width: 24,
                height: 24)
            subtitle.frame = NSRect(x: 34, y: 4, width: max(0, bounds.width - 42), height: 12)
        } else {
            title.frame = NSRect(x: 4, y: (bounds.height - 17) / 2, width: max(0, bounds.width - 15), height: 17)
        }
        setAccessibilityLabel(title.stringValue)
    }
}
