import AppKit
import AtlasCore
import QuickLook
import SwiftUI

/// The same native outline disclosure as Contents; SwiftUI hosts only the surrounding report.
struct DuplicateOutline: View {
    let groups: [DuplicateGroup]
    @ObservedObject var session: DuplicateSession
    @ObservedObject var store: AtlasStore
    let columns: DuplicateTableColumns
    let embedded: Bool
    let expansion: DuplicateExpansionState
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var focusedFile: String?

    var body: some View {
        DuplicateOutlineTable(
            groups: groups, session: session, store: store, columns: columns, embedded: embedded, expansion: expansion,
            focusedFile: $focusedFile,
            preview: { file, group in
                previewURLs = group.files.prefix(200).map { URL(fileURLWithPath: $0.path) }
                previewURL = URL(fileURLWithPath: file.path)
            },
            collapsed: { group in
                if let previewURL, group.files.contains(where: { $0.path == previewURL.path }) { self.previewURL = nil }
            }
        ).quickLookPreview($previewURL, in: previewURLs).onChange(of: previewURL) { previous, current in
            guard current == nil, let previous else { return }
            Task { @MainActor in
                await Task.yield()
                focusedFile = previous.path
            }
        }
    }
}

struct DuplicateOutlineTable: NSViewRepresentable {
    let groups: [DuplicateGroup]
    let session: DuplicateSession
    let store: AtlasStore
    let columns: DuplicateTableColumns
    let embedded: Bool
    let expansion: DuplicateExpansionState
    @Binding var focusedFile: String?
    let preview: (DuplicateFile, DuplicateGroup) -> Void
    let collapsed: (DuplicateGroup) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = DuplicateOutlineScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = DuplicateNativeOutline()
        table.headerView = nil
        table.indentationPerLevel = 0
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.rowHeight = FileListMetrics.pathRowHeight
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.columnAutoresizingStyle = .noColumnAutoresizing
        let check = NSTableColumn(identifier: .init("check"))
        check.width = FileListMetrics.checkWidth
        check.resizingMask = []
        table.addTableColumn(check)
        let column = NSTableColumn(identifier: .init("duplicate"))
        table.addTableColumn(column)
        table.outlineTableColumn = column
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        scroll.resized = { [weak coordinator = context.coordinator] width in coordinator?.resize(width) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        scroll.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        coordinator.table?.backgroundColor = NSColor(Palette.paper)
        coordinator.update()
    }
}

/// Native disclosure owns live expansion; this cache restores it without a SwiftUI relayout per click.
final class DuplicateExpansionState { var ids = Set<String>() }

final class DuplicateOutlineItem: NSObject {
    let group: DuplicateGroup
    let file: DuplicateFile?
    let more: Bool
    lazy var children: [DuplicateOutlineItem] = {
        var result = group.files.prefix(200).map { DuplicateOutlineItem(group: group, file: $0) }
        if group.files.count > 200 { result.append(DuplicateOutlineItem(group: group, more: true)) }
        return result
    }()
    init(group: DuplicateGroup, file: DuplicateFile? = nil, more: Bool = false) {
        self.group = group
        self.file = file
        self.more = more
    }
}

final class DuplicateNativeOutline: NSOutlineView {}

final class DuplicateOutlineScrollView: NSScrollView {
    var resized: ((CGFloat) -> Void)?
    override func layout() {
        super.layout()
        guard let table = documentView as? NSOutlineView, contentSize.width > 0 else { return }
        let width = contentSize.width
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if let column = table.tableColumns.last {
            let contentWidth = max(0, width - FileListMetrics.checkWidth)
            if abs(column.width - contentWidth) > 0.5 { column.width = contentWidth }
        }
        resized?(width)
    }
}
