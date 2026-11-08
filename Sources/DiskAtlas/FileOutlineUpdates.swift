import AppKit
import AtlasCore

extension FileTable.Coordinator {
    func childrenLoaded(_ item: FileOutlineNode) {
        guard let table, table.row(forItem: item) >= 0 else { return }
        suppressSelection = true
        table.reloadItem(item, reloadChildren: true)
        if requestedExpansions.remove(item.folderID) != nil || outline.expanded.contains(item.folderID) {
            table.expandItem(item)
        }
        restoreExpansions()
        suppressSelection = false
        updateDisplayedRows()
        updateSelection()
        scrollSelection(animated: false)
    }
    func restoreExpansions() {
        guard let table, outline.enabled else { return }
        for id in outline.expanded {
            guard let item = outline.item(id), table.row(forItem: item) >= 0, !table.isItemExpanded(item) else {
                continue
            }
            table.expandItem(item)
        }
    }
    func revealContext() {
        guard let table, outline.enabled, outline.revealPath.count > 1 else { return }
        let path = outline.revealPath
        for offset in 0..<(path.count - 1) {
            guard let item = outline.item(path[offset]) else { return }
            if !outline.contains(path[offset + 1], in: item) {
                requestedExpansions.insert(item.folderID)
                outline.load(item, including: path[offset + 1])
                return
            }
            if !table.isItemExpanded(item) { table.expandItem(item) }
        }
    }
    func updateDisplayedRows() {
        guard let table else { return }
        displayedIDs = Set((0..<table.numberOfRows).compactMap { entry(at: $0)?.id })
        let creation = parent.showCreationDate || outline.hasCreationDates
        table.tableColumns.first { $0.identifier.rawValue == "created" }?.isHidden = !creation
        table.enclosingScrollView?.needsLayout = true
        updateTrashControls()
        table.headerView?.needsDisplay = true
    }
}
