import AppKit
import AtlasCore

extension FileTable.Coordinator: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? FileOutlineNode
        if let node, outline.expandable(node), !outline.loaded(node), outlineView.isItemExpanded(node) {
            outline.load(node)
        }
        return outline.children(of: node).count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        outline.children(of: item as? FileOutlineNode)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileOutlineNode).map(outline.expandable) ?? false
    }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?)
        -> Any?
    { (item as? FileOutlineNode)?.entry?.name }
    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileOutlineNode, !outline.loaded(node) else { return }
        // shouldExpandItem is also an accessibility capability query: it must have no side effects.
        requestedExpansions.insert(node.folderID)
        outline.load(node)
        DispatchQueue.main.async { [weak self] in self?.table?.reloadItem(node) }
    }
    func outlineViewItemWillCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileOutlineNode else { return }
        requestedExpansions.remove(node.folderID)
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? FileOutlineNode { outline.expanded.insert(item.folderID) }
        updateDisplayedRows()
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? FileOutlineNode { outline.expanded.remove(item.folderID) }
        updateDisplayedRows()
    }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? FileOutlineNode)?.entry != nil
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, let table else { return }
        parent.selection = entry(at: table.selectedRow)?.id
    }
    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if let key = outlineView.sortDescriptors.first?.key, let field = EntrySort(rawValue: key) {
            parent.sortBy(field)
        }
    }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? FileOutlineNode)?.entry != nil && parent.showPaths ? 43 : 33
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { makeRowView() }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileOutlineNode else { return nil }
        if node.entry != nil { return cell(outlineView, column: tableColumn, row: outlineView.row(forItem: item)) }
        guard tableColumn?.identifier.rawValue == "name" else { return nil }
        let cell = OutlineMoreCell()
        let busy = outline.loading.contains(node.folderID)
        cell.button.title = L10n.text(busy ? "Загружаем…" : "Показать ещё") + " · " + node.remaining.formatted()
        cell.button.isEnabled = !busy
        cell.button.toolTip = L10n.text("Следующие 1 000 объектов")
        cell.action = { [weak self] in
            guard let self, let folder = outline.item(node.folderID) else { return }
            outline.load(folder, nextPage: true)
            outlineView.reloadItem(node)
        }
        return cell
    }
}

private final class OutlineMoreCell: NSTableCellView {
    let button = NSButton(title: "", target: nil, action: nil)
    var action: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 11)
        button.target = self
        button.action = #selector(pressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func pressed() { action?() }
}
