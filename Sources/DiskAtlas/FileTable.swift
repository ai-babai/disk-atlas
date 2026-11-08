import AppKit
import AtlasCore
import SwiftUI

/// Native, virtualized rows with the app palette. Selection does not rebuild cells.
struct FileTable: NSViewRepresentable {
    @ObservedObject var trash: FileTrashSession
    let reviewTrash: (Int) -> Void
    let trashEnabled: Bool
    var rows: [Entry]
    var index: PresentationIndex?
    var folderID: Int
    var hierarchical: Bool
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
    var preview: (Entry, [Entry]) -> Void
    @AppStorage("atlas.column.created") private var createdVisible = true
    @AppStorage("atlas.column.modified") private var modifiedVisible = true
    @AppStorage("atlas.column.share") private var shareVisible = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var createdColumnVisible: Bool { createdVisible }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = AtlasTableScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = AtlasTableView()
        table.headerView = AtlasHeaderView(frame: NSRect(x: 0, y: 0, width: 500, height: 28))
        table.autoresizesOutlineColumn = false
        table.indentationPerLevel = 14
        table.style = .plain
        table.allowsColumnResizing = true
        table.autosaveName = "atlas.files"
        table.autosaveTableColumns = true
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
        for (name, width) in [
            ("check", 44.0), ("name", 260.0), ("created", 92.0), ("modified", 92.0), ("size", 100.0), ("share", 65.0),
            ("trash", 30.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = width
            column.minWidth = name == "name" ? 180 : width
            column.resizingMask = name == "check" || name == "trash" ? [] : .userResizingMask
            let header = AtlasHeaderCell(textCell: name)
            header.press = { [weak coordinator = context.coordinator] in
                if name == "check" {
                    coordinator?.toggleVisible()
                    return
                }
                guard let field = EntrySort(rawValue: name) else { return }
                coordinator?.parent.sortBy(field)
            }
            if EntrySort(rawValue: name) != nil {
                column.sortDescriptorPrototype = NSSortDescriptor(key: name, ascending: name == "name")
            }
            if name == "check" { header.setAccessibilityLabel(L10n.text("Выбрать показанные объекты")) }
            column.headerCell = header
            table.addTableColumn(column)
        }
        table.outlineTableColumn = table.tableColumns.first { $0.identifier.rawValue == "name" }
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
        let appearance: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        let highContrast: NSAppearance.Name =
            scheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
        scroll.appearance = NSAppearance(named: contrast == .increased ? highContrast : appearance)
        table.backgroundColor = NSColor(Palette.paper)
        table.rowHeight = showPaths ? 43 : 33
        let titles = [
            "name": "Имя", "created": "Создан", "modified": "Изменён", "size": logical ? "Размер" : "На диске",
            "share": "Доля",
        ]
        for column in table.tableColumns {
            let key = column.identifier.rawValue
            column.headerCell.stringValue =
                L10n.text(titles[key] ?? "") + (key == sort.rawValue ? descending ? " ↓" : " ↑" : "")
            column.headerCell.font = .systemFont(ofSize: 10, weight: .medium)
            column.headerCell.alignment = key == "size" || key == "share" ? .right : .left
            if let header = column.headerCell as? AtlasHeaderCell { header.color = NSColor(Palette.sub) }
        }
        table.headerView?.needsDisplay = true
        table.tableColumns.first { $0.identifier.rawValue == "created" }?.isHidden =
            !(createdVisible && (showCreationDate || coordinator.outline.hasCreationDates))
        table.tableColumns.first { $0.identifier.rawValue == "modified" }?.isHidden = !modifiedVisible
        table.tableColumns.first { $0.identifier.rawValue == "share" }?.isHidden = !shareVisible
        scroll.needsLayout = true
        coordinator.reloadIfNeeded()
        coordinator.updateSelection()
        coordinator.scrollSelection(animated: !reduceMotion)
        coordinator.updateTrashControls()
        table.needsDisplay = true
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var parent: FileTable
        weak var table: NSOutlineView?
        let outline = FileOutlineModel()
        var displayedIDs = Set<Int>()
        var requestedExpansions = Set<Int>()
        var duplicateID: UUID?
        var revision = -1
        var scrollRequest = 0
        var language = ""
        var logical = false
        var showPaths = false
        var suppressSelection = false
        var trashAnchor: Int?
        let dateFormatter = DateFormatter()
        init(_ parent: FileTable) {
            self.parent = parent
            super.init()
            outline.changed = { [weak self] item in self?.childrenLoaded(item) }
        }
        private var needsReload: Bool {
            revision != parent.revision || language != parent.language || logical != parent.logical
                || showPaths != parent.showPaths || duplicateID != parent.duplicates?.id
                || outline.index !== parent.index || outline.enabled != parent.hierarchical
        }
        func reloadIfNeeded() {
            guard let table else { return }
            guard needsReload else { return }
            duplicateID = parent.duplicates?.id
            revision = parent.revision
            language = parent.language
            dateFormatter.locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
            dateFormatter.dateStyle = .short
            logical = parent.logical
            showPaths = parent.showPaths
            suppressSelection = true
            if outline.index !== parent.index || outline.folder != parent.folderID {
                table.collapseItem(nil, collapseChildren: true)
                requestedExpansions = []
            }
            outline.configure(
                index: parent.index, folder: parent.folderID, enabled: parent.hierarchical, rows: parent.rows,
                contextID: parent.contextID,
                query: FileOutlineQuery(logical: parent.logical, sort: parent.sort, descending: parent.descending))
            table.reloadData()
            restoreExpansions()
            suppressSelection = false
            updateDisplayedRows()
        }
        func updateSelection() {
            guard let table else { return }
            let desired = parent.selection.flatMap { outline.item($0) }.map { table.row(forItem: $0) } ?? -1
            if desired != table.selectedRow {
                suppressSelection = true
                table.selectRowIndexes(desired < 0 ? [] : IndexSet(integer: desired), byExtendingSelection: false)
                suppressSelection = false
            }
        }
        func scrollSelection(animated: Bool) {
            let request = parent.scrollRequest
            guard request > 0, scrollRequest != request else { return }
            revealContext()
            DispatchQueue.main.async { [weak self] in self?.performScroll(request, animated: animated) }
        }
        private func performScroll(_ request: Int, animated: Bool) {
            guard parent.scrollRequest == request, let table, let selection = parent.selection,
                let item = outline.item(selection), let scroll = table.enclosingScrollView
            else { return }
            let row = table.row(forItem: item)
            guard row >= 0 else { return }
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
        func toggleVisible() {
            guard parent.trashEnabled else { return }
            parent.trash.toggle(displayedIDs)
        }
        func updateTrashControls() {
            guard let table else { return }
            table.enumerateAvailableRowViews { _, row in
                for key in ["check", "trash"] {
                    let column = table.column(withIdentifier: NSUserInterfaceItemIdentifier(key))
                    if let cell = table.view(atColumn: column, row: row, makeIfNecessary: false) as? TrashTableCell {
                        configure(cell, row: row, checkbox: key == "check")
                    }
                }
            }
            if let header = table.tableColumns.first?.headerCell {
                header.setAccessibilityLabel(L10n.text("Выбрать показанные объекты"))
                let all = !displayedIDs.isEmpty && displayedIDs.isSubset(of: parent.trash.selected)
                header.image = NSImage(
                    systemSymbolName: all ? "checkmark.square.fill" : "square",
                    accessibilityDescription: L10n.text("Выбрать показанные объекты"))
            }
        }
        private func trashCell(_ table: NSTableView, key: NSUserInterfaceItemIdentifier, row: Int) -> TrashTableCell {
            let cell =
                (table.makeView(withIdentifier: key, owner: self) as? TrashTableCell)
                ?? TrashTableCell(checkbox: key.rawValue == "check")
            cell.identifier = key
            configure(cell, row: row, checkbox: key.rawValue == "check")
            return cell
        }
        private func configure(_ cell: TrashTableCell, row: Int, checkbox: Bool) {
            guard let entry = entry(at: row) else { return }
            cell.button.state = parent.trash.selected.contains(entry.id) ? .on : .off
            cell.button.isEnabled = parent.trashEnabled && !parent.trash.busy
            let label = L10n.text(checkbox ? "Выбрать для корзины" : "В корзину…") + ": " + entry.name
            cell.button.toolTip = label
            cell.button.setAccessibilityLabel(label)
            cell.action = { [weak self] in
                guard let self, parent.trashEnabled else { return }
                if checkbox { toggleCheckbox(entry.id) } else { parent.reviewTrash(entry.id) }
            }
        }
        private func toggleCheckbox(_ id: Int) {
            defer { trashAnchor = id }
            guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true, let table, let anchor = trashAnchor,
                let first = (0..<table.numberOfRows).first(where: { entry(at: $0)?.id == anchor }),
                let last = (0..<table.numberOfRows).first(where: { entry(at: $0)?.id == id })
            else {
                parent.trash.toggle(id)
                return
            }
            let range = Set((min(first, last)...max(first, last)).compactMap { entry(at: $0)?.id })
            if parent.trash.selected.contains(id) {
                parent.trash.selected.subtract(range)
            } else {
                parent.trash.selected.formUnion(range)
            }
        }
        func entry(at row: Int) -> Entry? { (table?.item(atRow: row) as? FileOutlineNode)?.entry }
        func makeRowView() -> NSTableRowView { AtlasRowView() }
        func cell(_ tableView: NSOutlineView, column tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let entry = entry(at: row), let key = tableColumn?.identifier else { return nil }
            if key.rawValue == "check" || key.rawValue == "trash" { return trashCell(tableView, key: key, row: row) }
            let cell =
                (tableView.makeView(withIdentifier: key, owner: self) as? AtlasCell) ?? AtlasCell(identifier: key)
            let bytes = parent.logical ? entry.logicalBytes : entry.bytes
            switch key.rawValue {
            case "name": configureName(cell, entry: entry)
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
        private func configureName(_ cell: AtlasCell, entry: Entry) {
            cell.title.stringValue = entry.name
            cell.subtitle.stringValue = parent.showPaths ? entry.path : ""
            cell.icon.image = NSImage(systemSymbolName: entry.kind.symbol, accessibilityDescription: nil)
            cell.icon.contentTintColor = NSColor(entry.kind.tint)
            cell.toolTip = entry.path
            let groupID = parent.duplicates?.byPath[entry.path]
            cell.duplicateButton.isHidden = groupID == nil
            cell.duplicateAction = { [weak self] in self?.parent.showDuplicates(entry.path) }
            cell.duplicateButton.toolTip =
                L10n.text("Показать все копии") + " · " + (parent.duplicates.map { L10n.date($0.checkedAt) } ?? "")
            cell.duplicateButton.setAccessibilityLabel(L10n.text("Дубликаты") + ": " + entry.name)
            cell.setLoading(outline.loading.contains(entry.id))
        }
        @objc func openRow() {
            guard let table, let entry = entry(at: table.selectedRow) else { return }
            parent.open(entry.id)
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard let entry = entry(at: row) else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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
            guard let table, let entry = entry(at: table.selectedRow) else { return }
            parent.reveal(entry)
        }
        @objc func previewRow() {
            guard let table, let entry = entry(at: table.selectedRow) else { return }
            var items = (0..<min(table.numberOfRows, 1000)).compactMap { self.entry(at: $0) }
            if !items.contains(where: { $0.id == entry.id }) { items.insert(entry, at: 0) }
            parent.preview(entry, items)
        }
        @objc private func copyRow() {
            guard let table, let entry = entry(at: table.selectedRow) else { return }
            parent.copyPath(entry.path)
        }
    }
}

private final class AtlasHeaderCell: NSTableHeaderCell {
    var press: (() -> Void)?
    var color = NSColor.secondaryLabelColor
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let image {
            image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))?.draw(
                in: NSRect(x: cellFrame.midX - 7, y: cellFrame.midY - 7, width: 14, height: 14))
            return
        }
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
            if name == "check" {
                column.headerCell.drawInterior(withFrame: rect, in: self)
                continue
            }
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
        let location = convert(event.locationInWindow, from: nil)
        if tableView.tableColumns.indices.contains(where: { index in
            let column = tableView.tableColumns[index]
            return !column.isHidden && column.resizingMask.contains(.userResizingMask)
                && abs(headerRect(ofColumn: index).maxX - location.x) < 5
        }) {
            super.mouseDown(with: event)
            return
        }
        let column = column(at: location)
        if column >= 0, column < tableView.tableColumns.count {
            (tableView.tableColumns[column].headerCell as? AtlasHeaderCell)?.press?()
        }
    }
}

private final class AtlasTableScrollView: NSScrollView {
    private var viewportWidth: CGFloat = -1
    private var visibleColumns = ""
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView,
            let name = table.tableColumns.first(where: { $0.identifier.rawValue == "name" })
        else { return }
        let fixedWidth = table.tableColumns.filter { !$0.isHidden && $0.identifier.rawValue != "name" }.reduce(
            CGFloat(0)
        ) { $0 + $1.width }
        let columns = table.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue }.joined()
        if viewportWidth != contentView.bounds.width || visibleColumns != columns {
            viewportWidth = contentView.bounds.width
            visibleColumns = columns
            name.width = max(name.minWidth, viewportWidth - 16 - fixedWidth)
        }
        let width = max(fixedWidth + name.width, contentView.bounds.width - 16)
        if abs(table.frame.width - width) > 0.5 {
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
            table.tile()
        }
    }
}

private final class AtlasTableView: NSOutlineView {
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
    let progress = NSProgressIndicator()
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
            progress.style = .spinning
            progress.controlSize = .small
            progress.isDisplayedWhenStopped = false
            addSubview(progress)
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
    func setLoading(_ loading: Bool) {
        icon.isHidden = loading
        if loading { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
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
            progress.frame = icon.frame
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
