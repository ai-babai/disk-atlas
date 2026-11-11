import AppKit
import AtlasCore
import SwiftUI

extension DuplicateOutlineTable {
    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: DuplicateOutlineTable
        weak var table: DuplicateNativeOutline?
        var items: [DuplicateOutlineItem] = []
        var signature: [String] = []
        var lookupID: UUID?
        var dateColumns: [Bool] = []
        var synchronizing = false
        var scrollRequest: String?
        var width: CGFloat = 0
        var contentWidth: CGFloat = 0
        var contentLeading: CGFloat = 16
        var contentTrailing: CGFloat = 8
        let pathMeasurement = NSTextField(wrappingLabelWithString: "")
        var restoredFocus: String?
        init(_ parent: DuplicateOutlineTable) {
            self.parent = parent
            super.init()
            pathMeasurement.font = FileListMetrics.secondaryFont
        }
        func update() {
            guard let table else { return }
            let newWidth = table.enclosingScrollView?.contentSize.width ?? table.bounds.width
            let resized = abs(width - newWidth) > 0.5
            width = newWidth
            if resized { table.tableColumns.last?.width = max(0, newWidth - FileListMetrics.checkWidth) }
            let next = parent.groups.map { $0.id + ":" + String($0.files.count) }
            let dates = [parent.columns.created, parent.columns.modified]
            let metricsChanged = resized || dateColumns != dates
            dateColumns = dates
            let reload = signature != next || lookupID != parent.session.lookup?.id
            synchronizing = true
            if reload {
                signature = next
                lookupID = parent.session.lookup?.id
                items = parent.groups.map { DuplicateOutlineItem(group: $0) }
                table.reloadData()
                measureColumns()
                for item in items where parent.expansion.ids.contains(item.group.id) { table.expandItem(item) }
            }
            synchronizing = false
            if metricsChanged {
                measureColumns()
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
            }
            refreshVisibleRows()
            focusRequestedGroup()
        }
        func refreshVisibleRows() {
            guard let table else { return }
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return }
            for row in range.location..<NSMaxRange(range) {
                guard let item = table.item(atRow: row) as? DuplicateOutlineItem else { continue }
                for column in 0..<2 {
                    if let view = table.view(atColumn: column, row: row, makeIfNecessary: false) {
                        configure(view, item: item)
                    }
                }
            }
            restorePreviewFocus()
        }
        func resize(_ newWidth: CGFloat) {
            guard abs(width - newWidth) > 0.5, let table else { return }
            width = newWidth
            measureColumns()
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
        }
        func measureColumns() {
            guard let table, table.numberOfRows > 0 else { return }
            let frame = table.frameOfCell(atColumn: 1, row: 0)
            contentWidth = frame.width
            let inset = frame.minX - FileListMetrics.checkWidth
            contentLeading = max(0, 32 - inset)
            let rightInset = (table.tableColumns.last?.width ?? 0) - inset - frame.width
            contentTrailing = max(0, 8 - rightInset)
        }
        func toggle(_ item: DuplicateOutlineItem) {
            guard let table else { return }
            // A SwiftUI button can inherit a zero-duration AppKit transaction.
            // Use the normal native disclosure context, rather than a SwiftUI row transition.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = parent.reduceMotion ? 0 : 0.25
                context.timingFunction = nil
                let outline = parent.reduceMotion ? table : table.animator()
                if table.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
            }
        }
        func focusRequestedGroup() {
            guard let id = parent.session.focusedGroupID else {
                scrollRequest = nil
                return
            }
            guard scrollRequest != id, let table, let item = items.first(where: { $0.group.id == id }) else { return }
            scrollRequest = id
            DispatchQueue.main.async { [weak self, weak item] in
                guard let self, let item, parent.session.focusedGroupID == id else { return }
                table.expandItem(item)
                table.scrollRowToVisible(table.row(forItem: item))
            }
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? DuplicateOutlineItem else { return items.count }
            return item.file == nil && !item.more ? item.children.count : 0
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? DuplicateOutlineItem)?.children[index] ?? items[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? DuplicateOutlineItem else { return false }
            return item.file == nil && !item.more
        }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let item = item as? DuplicateOutlineItem, let file = item.file else {
                return FileListMetrics.pathRowHeight
            }
            let dates =
                CGFloat((parent.columns.created ? 1 : 0) + (parent.columns.modified ? 1 : 0))
                * FileListMetrics.dateWidth
            let textWidth = max(
                1,
                contentWidth - contentLeading - contentTrailing - dates - DuplicateTableColumns.copiesWidth
                    - FileListMetrics.sizeWidth - DuplicateTableColumns.actionsWidth - 33)
            pathMeasurement.stringValue = file.path
            let size =
                pathMeasurement.cell?.cellSize(
                    forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)) ?? .zero
            return max(FileListMetrics.pathRowHeight, ceil(size.height) + 27)
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { AtlasRowView() }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? DuplicateOutlineItem else { return nil }
            let check = tableColumn?.identifier.rawValue == "check"
            let id = NSUserInterfaceItemIdentifier(check ? "duplicate.check" : "duplicate.row")
            let view =
                outlineView.makeView(withIdentifier: id, owner: nil)
                ?? (check ? TrashTableCell(checkbox: true) : DuplicateContentCell())
            view.identifier = id
            configure(view, item: item)
            return view
        }
        func outlineViewItemDidExpand(_ notification: Notification) { disclosureChanged(notification, expanded: true) }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            disclosureChanged(notification, expanded: false)
        }
        func disclosureChanged(_ notification: Notification, expanded: Bool) {
            guard !synchronizing, let item = notification.userInfo?["NSObject"] as? DuplicateOutlineItem else { return }
            if expanded {
                parent.expansion.ids.insert(item.group.id)
            } else {
                parent.expansion.ids.remove(item.group.id)
                parent.collapsed(item.group)
            }
        }
    }
}
