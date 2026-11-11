import AppKit
import AtlasCore

extension DuplicateOutlineTable.Coordinator {
    func configure(_ view: NSView, item: DuplicateOutlineItem) {
        if let check = view as? TrashTableCell { configureCheck(check, item: item) }
        if let cell = view as? DuplicateContentCell { configureContent(cell, item: item) }
    }
    private func configureCheck(_ cell: TrashTableCell, item: DuplicateOutlineItem) {
        cell.button.isHidden = item.more
        cell.button.isEnabled = !parent.session.busy
        let selected = parent.session.trashSelection
        if let file = item.file {
            cell.button.state = selected.paths.contains(file.path) ? .on : .off
            cell.button.setAccessibilityLabel(
                L10n.text("Выбрать для корзины") + ": " + URL(fileURLWithPath: file.path).lastPathComponent)
        } else {
            let count = selected.count(in: item.group)
            cell.button.state = count == 0 ? .off : count == item.group.files.count ? .on : .mixed
            cell.button.setAccessibilityLabel(
                L10n.text("Выбрать все копии группы") + ": " + (item.group.displayName ?? ""))
        }
        cell.button.allowsMixedState = cell.button.state == .mixed
        cell.action = { [weak self, weak cell] in
            guard let self, !parent.session.busy else { return }
            cell?.window?.makeFirstResponder(cell?.button)
            parent.focusedFile = nil
            if let file = item.file {
                parent.session.trashSelection.toggle(file, in: item.group)
            } else {
                parent.session.trashSelection.toggle(item.group)
            }
        }
    }
    private func configureContent(_ cell: DuplicateContentCell, item: DuplicateOutlineItem) {
        let group = item.group
        let count = parent.session.trashSelection.count(in: group)
        cell.configure(
            item, columns: parent.columns, selectedCount: count,
            fileSelected: item.file.map { parent.session.trashSelection.paths.contains($0.path) } ?? false,
            highlighted: parent.embedded && parent.store.duplicateSelectionID == group.id
                && parent.store.duplicateSelectedFile?.path == item.file?.path, busy: parent.session.busy,
            leading: contentLeading, trailing: contentTrailing)
        cell.selectAction = { [weak self] in self?.select(item) }
        cell.previewAction = { [weak self] in
            guard let self, let file = item.file else { return }
            parent.focusedFile = nil
            parent.preview(file, group)
        }
        cell.revealAction = { [weak self] in if let file = item.file { self?.parent.session.reveal(file) } }
        cell.trashAction = { [weak self] in
            guard let self else { return }
            if let file = item.file {
                parent.session.reviewTrash([file.path])
            } else {
                parent.session.reviewTrash(group)
            }
        }
    }
    private func select(_ item: DuplicateOutlineItem) {
        if let file = item.file {
            if parent.embedded { parent.store.focusDuplicateFile(file, in: item.group) }
        } else if parent.embedded {
            parent.store.focusDuplicateGroup(item.group)
        } else {
            toggle(item)
        }
    }
    func restorePreviewFocus() {
        let path = parent.focusedFile
        guard path != restoredFocus else { return }
        restoredFocus = path
        guard let path, let table, table.window?.isKeyWindow == true,
            let group = items.first(where: { $0.group.files.prefix(200).contains { $0.path == path } }),
            let item = group.children.first(where: { $0.file?.path == path })
        else { return }
        let row = table.row(forItem: item)
        guard row >= 0 else { return }
        table.scrollRowToVisible(row)
        if let cell = table.view(atColumn: 1, row: row, makeIfNecessary: true) {
            table.window?.makeFirstResponder(cell)
        }
    }
}
