import AppKit
import AtlasCore

final class FileOutlineNode: NSObject {
    let entry: Entry?
    let folderID: Int
    var remaining = 0
    init(_ entry: Entry) {
        self.entry = entry
        folderID = entry.id
    }
    init(moreIn folder: Int) {
        entry = nil
        folderID = folder
    }
}

struct FileOutlineQuery: Equatable {
    let logical: Bool
    let sort: EntrySort
    let descending: Bool
}

/// Stable native item identities and lazy, bounded child pages from the existing index.
@MainActor final class FileOutlineModel {
    private(set) var roots: [FileOutlineNode] = []
    private(set) var index: PresentationIndex?
    private(set) var folder = 0
    private(set) var enabled = false
    private(set) var revealPath: [Int] = []
    private(set) var loading = Set<Int>()
    private(set) var hasCreationDates = false
    var expanded = Set<Int>()
    var changed: ((FileOutlineNode) -> Void)?
    private var query = FileOutlineQuery(logical: false, sort: .size, descending: true)
    private var nodes: [Int: FileOutlineNode] = [:]
    private var pages: [Int: [FileOutlineNode]] = [:]
    private var more: [Int: FileOutlineNode] = [:]
    private var limits: [Int: Int] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var tokens: [Int: UUID] = [:]

    func configure(
        index: PresentationIndex?, folder: Int, enabled: Bool, rows: [Entry], contextID: Int?, query: FileOutlineQuery
    ) {
        let reset = self.index !== index || self.folder != folder
        if reset || self.query != query { invalidatePages() }
        if reset {
            nodes = [:]
            more = [:]
            expanded = []
            hasCreationDates = false
        }
        self.index = index
        self.folder = folder
        self.enabled = enabled
        self.query = query
        revealPath = enabled ? path(to: contextID) : []
        let nested = revealPath.count > 1
        roots = rows.filter { !nested || $0.id != contextID }.map(node)
        if nested, let first = revealPath.first, !roots.contains(where: { $0.entry?.id == first }),
            let entry = index?.snapshot.entries[first]
        {
            roots.insert(node(entry), at: 0)
        }
    }
    private func invalidatePages() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        tokens = [:]
        loading = []
        pages = [:]
        limits = [:]
    }
    private func node(_ entry: Entry) -> FileOutlineNode {
        if let cached = nodes[entry.id] { return cached }
        let value = FileOutlineNode(entry)
        nodes[entry.id] = value
        if entry.created != nil { hasCreationDates = true }
        return value
    }
    func item(_ id: Int) -> FileOutlineNode? { nodes[id] }
    func children(of item: FileOutlineNode?) -> [FileOutlineNode] {
        guard let item else { return roots }
        return enabled ? pages[item.folderID] ?? [] : []
    }
    func expandable(_ item: FileOutlineNode) -> Bool {
        enabled && item.entry?.isDirectory == true && item.entry?.children.isEmpty == false
    }
    func loaded(_ item: FileOutlineNode) -> Bool { pages[item.folderID] != nil }
    func contains(_ id: Int, in item: FileOutlineNode) -> Bool {
        pages[item.folderID]?.contains { $0.entry?.id == id } == true
    }
    func load(_ item: FileOutlineNode, nextPage: Bool = false, including: Int? = nil) {
        let id = item.folderID
        guard let index, !loading.contains(id) else { return }
        let limit = (limits[id] ?? 1000) + (nextPage ? 1000 : 0)
        let token = UUID()
        tokens[id] = token
        loading.insert(id)
        let query = query
        tasks[id] = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                index.rows(
                    folder: id, logical: query.logical, query: "", kinds: [], filesOnly: false, limit: limit,
                    sort: query.sort, descending: query.descending, including: including)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, tokens[id] == token else { return }
            apply(result.entries, count: result.count, item: item, limit: limit)
        }
    }
    private func apply(_ entries: [Entry], count: Int, item: FileOutlineNode, limit: Int) {
        let id = item.folderID
        limits[id] = limit
        var children = entries.map(node)
        if count > entries.count {
            let pager = more[id] ?? FileOutlineNode(moreIn: id)
            pager.remaining = count - entries.count
            more[id] = pager
            children.append(pager)
        }
        pages[id] = children
        loading.remove(id)
        tasks[id] = nil
        tokens[id] = nil
        changed?(item)
    }
    private func path(to id: Int?) -> [Int] {
        guard let index else { return [] }
        var result: [Int] = []
        var cursor = id
        while let current = cursor, current != folder {
            result.append(current)
            cursor = index.snapshot.entries[current].parent
        }
        return cursor == folder ? result.reversed() : []
    }
}
