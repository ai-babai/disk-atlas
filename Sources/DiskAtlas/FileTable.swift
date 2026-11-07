import SwiftUI
import AppKit
import AtlasCore

/// Native, virtualized rows with the app palette. Selection does not rebuild cells.
struct FileTable: NSViewRepresentable {
    var rows: [Entry]
    var logical: Bool
    var folderBytes: Int64
    var revision: Int
    var language: String
    var showPaths: Bool
    var showCreationDate: Bool
    @Binding var selection: Int?
    var open: (Int) -> Void
    var reveal: (Entry) -> Void
    var copyPath: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = AtlasTableScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = AtlasTableView()
        table.headerView = nil
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
        for (name, width) in [("name", 260.0), ("created", 92.0), ("modified", 92.0), ("size", 100.0), ("share", 65.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = width
            column.minWidth = name == "name" ? 80 : width
            column.resizingMask = name == "name" ? .autoresizingMask : []
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
        table.tableColumns.first { $0.identifier.rawValue == "created" }?.isHidden = !showCreationDate
        scroll.needsLayout = true
        if coordinator.revision != revision || coordinator.language != language || coordinator.logical != logical || coordinator.showPaths != showPaths {
            coordinator.revision = revision
            coordinator.language = language
            coordinator.dateFormatter.locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
            coordinator.dateFormatter.dateStyle = .short
            coordinator.logical = logical
            coordinator.showPaths = showPaths
            coordinator.suppressSelection = true
            table.reloadData()
            coordinator.suppressSelection = false
        }
        let desired = selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? -1
        if desired != table.selectedRow {
            coordinator.suppressSelection = true
            table.selectRowIndexes(desired < 0 ? [] : IndexSet(integer: desired), byExtendingSelection: false)
            coordinator.suppressSelection = false
        }
        table.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FileTable
        weak var table: NSTableView?
        var revision = -1
        var language = ""
        var logical = false
        var showPaths = false
        var suppressSelection = false
        let dateFormatter = DateFormatter()
        init(_ parent: FileTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { AtlasRowView() }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelection, let table else { return }
            let row = table.selectedRow
            parent.selection = row >= 0 && row < parent.rows.count ? parent.rows[row].id : nil
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count, let key = tableColumn?.identifier else { return nil }
            let entry = parent.rows[row]
            let cell = (tableView.makeView(withIdentifier: key, owner: self) as? AtlasCell) ?? AtlasCell(identifier: key)
            let bytes = parent.logical ? entry.logicalBytes : entry.bytes
            switch key.rawValue {
            case "name":
                cell.title.stringValue = entry.name
                cell.subtitle.stringValue = parent.showPaths ? entry.path : ""
                cell.icon.image = NSImage(systemSymbolName: entry.kind.symbol, accessibilityDescription: nil)
                cell.icon.contentTintColor = NSColor(entry.kind.tint)
                cell.toolTip = entry.path
            case "size": cell.title.stringValue = byteString(bytes)
            case "created", "modified":
                let date = key.rawValue == "created" ? entry.created : entry.modified
                cell.title.stringValue = date.map { dateFormatter.string(from: $0) } ?? "—"
                cell.toolTip = date.map { L10n.date($0) } ?? L10n.text("Дата создания не сохранена в этом снимке")
            default:
                let share = Double(bytes) / Double(max(1, parent.folderBytes)) * 100
                let number = String(format: "%.1f", share)
                cell.title.stringValue = (parent.language == "ru" ? number.replacingOccurrences(of: ".", with: ",") : number) + "%"
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
            if entry.isDirectory { add(menu, L10n.text("Открыть папку"), #selector(openRow)) }
            add(menu, L10n.text("Показать в Finder"), #selector(revealRow))
            add(menu, L10n.text("Скопировать путь"), #selector(copyRow))
        }
        private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        @objc private func revealRow() {
            guard let table, table.selectedRow >= 0 else { return }
            parent.reveal(parent.rows[table.selectedRow])
        }
        @objc private func copyRow() {
            guard let table, table.selectedRow >= 0 else { return }
            parent.copyPath(parent.rows[table.selectedRow].path)
        }
    }
}

private final class AtlasTableScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, let name = table.tableColumns.first else { return }
        let fixedWidth = table.tableColumns.dropFirst().filter { !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width }
        let width = max(0, contentView.bounds.width)
        let nameWidth = max(name.minWidth, width - fixedWidth)
        if abs(name.width - nameWidth) > 0.5 { name.width = nameWidth }
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
    }
}

private final class AtlasTableView: NSTableView {
    var returnAction: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { returnAction?() } else { super.keyDown(with: event) }
    }
}

private final class AtlasRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Palette.paper).setFill(); dirtyRect.fill()
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
    private let isName: Bool
    private let isDate: Bool
    init(identifier: NSUserInterfaceItemIdentifier) {
        isName = identifier.rawValue == "name"
        isDate = identifier.rawValue == "created" || identifier.rawValue == "modified"
        super.init(frame: .zero)
        self.identifier = identifier
        title.font = isName ? .systemFont(ofSize: 12, weight: .medium) : .monospacedDigitSystemFont(ofSize: isDate ? 10 : 11, weight: .regular)
        title.textColor = NSColor(isDate ? Palette.sub : Palette.ink)
        title.lineBreakMode = .byTruncatingTail
        title.alignment = isName || isDate ? .left : .right
        subtitle.font = .systemFont(ofSize: 9)
        subtitle.textColor = NSColor(Palette.sub)
        subtitle.lineBreakMode = .byTruncatingMiddle
        addSubview(title)
        if isName { addSubview(icon); addSubview(subtitle) }
        textField = title
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        if isName {
            icon.frame = NSRect(x: 9, y: (bounds.height - 16) / 2, width: 16, height: 16)
            let hasSubtitle = !subtitle.stringValue.isEmpty
            title.frame = NSRect(x: 34, y: hasSubtitle ? bounds.height / 2 : (bounds.height - 17) / 2, width: max(0, bounds.width - 42), height: 17)
            subtitle.frame = NSRect(x: 34, y: 4, width: max(0, bounds.width - 42), height: 12)
        } else {
            title.frame = NSRect(x: 4, y: (bounds.height - 17) / 2, width: max(0, bounds.width - 15), height: 17)
        }
        setAccessibilityLabel(title.stringValue)
    }
}
