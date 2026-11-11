import AtlasCore
import SwiftUI

/// One cancellable metadata pass per chosen group; no source reads or per-frame path searches.
final class DuplicateMapFocus: Sendable {
    let index: PresentationIndex
    let group: DuplicateGroup
    let file: DuplicateFile?
    var selectedCount: Int { file == nil ? group.files.count : 1 }
    let counts: [Int: Int]
    struct Location: Identifiable, Sendable {
        let path: String
        let count: Int
        var id: String { path }
    }
    let locations: [Location]
    let folderCount: Int
    enum Detail { case copies, folders, overview }
    static let markerLimit = 12
    init(
        index: PresentationIndex, group: DuplicateGroup, file: DuplicateFile?, counts: [Int: Int],
        locations: [Location], folderCount: Int
    ) {
        self.index = index
        self.group = group
        self.file = file
        self.counts = counts
        self.locations = locations
        self.folderCount = folderCount
    }
    func copies(in tile: MapTile, parent: Int, siblings: [MapTile]) -> Int {
        if tile.id >= 0 { return counts[tile.id, default: 0] }
        return max(
            0, counts[parent, default: 0] - siblings.filter { $0.id >= 0 }.reduce(0) { $0 + counts[$1.id, default: 0] })
    }
    func detail(in parent: Int, tiles: [MapTile]) -> Detail {
        guard counts[parent, default: 0] > Self.markerLimit else { return .copies }
        let occupied = tiles.lazy.filter { self.copies(in: $0, parent: parent, siblings: tiles) > 0 }.prefix(
            Self.markerLimit + 1
        ).count
        return occupied > Self.markerLimit ? .overview : .folders
    }
    private static func folders(_ files: [DuplicateFile]) throws -> (locations: [Location], count: Int) {
        var folders: [String: Int] = [:]
        for (offset, file) in files.enumerated() {
            if offset % 512 == 0 { try Task.checkCancellation() }
            folders[(file.path as NSString).deletingLastPathComponent, default: 0] += 1
        }
        var best: [Location] = []
        for (offset, item) in folders.enumerated() {
            if offset % 512 == 0 { try Task.checkCancellation() }
            best.append(Location(path: item.key, count: item.value))
            best.sort { $0.count == $1.count ? $0.path < $1.path : $0.count > $1.count }
            if best.count > 4 { best.removeLast() }
        }
        return (best, folders.count)
    }
    func locationName(_ path: String) -> String {
        guard let root = index.snapshot.scanRoots.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            return (path as NSString).lastPathComponent
        }
        return (root as NSString).lastPathComponent + path.dropFirst(root.count)
    }
    static func build(_ group: DuplicateGroup, index: PresentationIndex, file: DuplicateFile? = nil) throws
        -> DuplicateMapFocus
    {
        let files = file.map { [$0] } ?? group.files
        let paths = Set(files.map(\.path))
        var counts: [Int: Int] = [:]
        for entry in index.snapshot.entries {
            if entry.id % 512 == 0 { try Task.checkCancellation() }
            guard paths.contains(entry.path) else { continue }
            var cursor: Int? = entry.id
            while let id = cursor {
                counts[id, default: 0] += 1
                cursor = index.snapshot.entries[id].parent
            }
        }
        try Task.checkCancellation()
        let folders = try Self.folders(files)
        return DuplicateMapFocus(
            index: index, group: group, file: file, counts: counts, locations: folders.locations,
            folderCount: folders.count)
    }
}

extension AtlasStore {
    var inspectedDuplicateGroup: DuplicateGroup? { duplicateList && !showDuplicates ? duplicateSelectedGroup : nil }
    var visibleDuplicateFocus: DuplicateMapFocus? {
        guard duplicateList, !showDuplicates, let focus = duplicateMapFocus, focus.index === index else { return nil }
        return focus
    }
    func prepareDuplicateList() {
        guard let snapshot else { return }
        if !duplicates.busy && duplicates.snapshotCreated != snapshot.created {
            duplicates.select(snapshot, id: activeHistoryID, prepareIfMissing: true)
        }
        updateDuplicateListScope()
        if !duplicates.busy && duplicates.plan == nil && duplicates.report == nil {
            duplicates.prepare(snapshot, id: activeHistoryID)
        }
    }
    func updateDuplicateListScope() {
        guard duplicateList, duplicates.snapshotCreated == snapshot?.created, let folder else { return }
        let path = isVirtual(folder) ? nil : folder.path
        if duplicates.scopePath != path {
            duplicates.trashSelection = DuplicateTrashSelection()
            duplicates.focusedGroupID = nil
            duplicates.scopePath = path
        }
    }
    func clearDuplicateFocus() {
        duplicateFocusTask?.cancel()
        duplicateFocusWorker?.cancel()
        duplicateFocusTask = nil
        duplicateFocusWorker = nil
        duplicateMapFocus = nil
        duplicateSelectedGroup = nil
        duplicateSelectedFile = nil
    }
    func focusDuplicateGroup(_ group: DuplicateGroup) { focusDuplicate(group, file: nil) }
    func focusDuplicateFile(_ file: DuplicateFile, in group: DuplicateGroup) { focusDuplicate(group, file: file) }
    private func focusDuplicate(_ group: DuplicateGroup, file: DuplicateFile?) {
        guard let index, duplicates.snapshotCreated == snapshot?.created else { return }
        if duplicateSelectionID == group.id, duplicateSelectedFile?.path == file?.path { return }
        clearMapSelection()
        duplicateSelectedGroup = group
        duplicateSelectedFile = file
        let worker = Task.detached(priority: .userInitiated) {
            try DuplicateMapFocus.build(group, index: index, file: file)
        }
        duplicateFocusWorker = worker
        duplicateFocusTask = Task {
            guard let focus = try? await worker.value, !Task.isCancelled, self.index === index,
                duplicateSelectionID == group.id, duplicateSelectedFile?.path == file?.path
            else { return }
            duplicateMapFocus = focus
        }
    }
    func showDuplicateOverview(_ group: DuplicateGroup) {
        let file = duplicateSelectedFile
        navigate(0)
        focusDuplicate(group, file: file)
    }
}

struct DuplicateMapSelectionInfo: View {
    let focus: DuplicateMapFocus
    @ObservedObject var store: AtlasStore
    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.text("На карте: ") + "\(focus.counts[store.folderID, default: 0]) / \(focus.selectedCount)")
                .monospacedDigit().foregroundStyle(Palette.sub)
            if focus.counts[store.folderID, default: 0] < focus.selectedCount, store.folderID != 0 {
                Button(L10n.text("Обзор")) { store.showDuplicateOverview(focus.group) }.buttonStyle(.plain)
            }
            Button {
                store.clearMapSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).help(L10n.text("Снять выделение")).accessibilityLabel(L10n.text("Снять выделение"))
        }.font(.system(size: 10)).fixedSize()
    }
}

struct DuplicateMapInspector: View {
    let group: DuplicateGroup
    let focus: DuplicateMapFocus?
    @ObservedObject var store: AtlasStore
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: L10n.text("Дубликаты"))
                    Text(group.displayName ?? "").font(.system(size: 18, weight: .semibold)).textSelection(.enabled)
                    fact("Копии", value: group.files.count.formatted())
                    fact("Размер копии", value: byteString(group.fileBytes))
                    fact("Повторы", value: byteString(group.repeatedBytes))
                    Divider().overlay(Palette.line)
                    folders
                }.font(.system(size: 11)).frame(width: max(0, geometry.size.width - 44), alignment: .leading).padding(
                    22)
            }
        }.background(Palette.paper).transaction { $0.animation = nil }
    }
    @ViewBuilder private var folders: some View {
        SectionLabel(text: L10n.text("Папки") + " · " + (focus?.folderCount.formatted() ?? "—"))
        if let focus {
            ForEach(focus.locations.prefix(4)) { location in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Palette.accent)
                    Text(focus.locationName(location.path)).lineLimit(2).help(location.path)
                    Spacer(minLength: 4)
                    Text(location.count.formatted()).monospacedDigit().foregroundStyle(Palette.sub)
                }
            }
            if focus.folderCount > focus.locations.count {
                Text("+ \(focus.folderCount - focus.locations.count)").foregroundStyle(Palette.sub)
            }
        }
    }
    private func fact(_ title: String, value: String) -> some View {
        HStack {
            Text(L10n.text(title)).foregroundStyle(Palette.sub)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

}
