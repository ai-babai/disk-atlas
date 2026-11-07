import SwiftUI
import UniformTypeIdentifiers
import AtlasCore

@MainActor final class AtlasStore: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var folderID = 0 { didSet { refreshRows() } }
    @Published var selection: Int?
    @Published var query = "" { didSet { refreshRows() } }
    @Published var selectedKinds: Set<FileKind> = [] { didSet { refreshRows() } }
    @Published var largestFiles = false { didSet { refreshRows() } }
    @Published var logical = false { didSet { refreshRows() } }
    @Published var scanning = false
    @Published var progressCount = 0
    @Published var progressBytes: Int64 = 0
    @Published var progressMetadataBytes: Int64 = 0
    @Published var progressPath = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var showIssues = false
    @Published var showAgent = false
    @Published var showSourcePicker = false
    @Published var pendingPaths: [String] = []
    @Published var appearance = "system"
    @Published var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    @Published var inspectorVisible = UserDefaults.standard.object(forKey: "inspectorVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: "inspectorVisible") }
    }
    @Published var language = L10n.language {
        didSet { L10n.language = language; notice = nil }
    }
    @Published var index: PresentationIndex?
    @Published var rows: [Entry] = [] { didSet { rowRevision += 1 } }
    @Published var rowRevision = 0
    @Published var rowCount = 0
    @Published var preparing = false
    @Published var loadingTitle: String?
    @Published var loadingStage = "Читаем снимок…"
    @Published var loadingHistoryID: UUID?
    @Published var rowsLoading = false
    @Published var historyRecords: [ScanHistoryRecord] = []
    @Published var activeHistoryID: UUID?
    @Published var savingHistory = 0
    @Published var showHistory = false
    @Published var snapshotArchiveBytes: Int64?
    @Published var snapshotMetadataEstimate: Int64?
    @Published var historyStorageBytes: Int64 = 0
    @Published var deletingHistory = false
    @Published var skipHistoryDeleteConfirmation = UserDefaults.standard.bool(forKey: "atlas.skipHistoryDeleteConfirmation") {
        didSet { UserDefaults.standard.set(skipHistoryDeleteConfirmation, forKey: "atlas.skipHistoryDeleteConfirmation") }
    }
    private let history: ScanHistory
    private var rowTask: Task<Void, Never>?
    private var rowWorker: Task<(entries: [Entry], count: Int), Never>?
    private var rowGeneration = 0
    private var cancellation: ScanCancellation?

    init(history: ScanHistory = ScanHistory()) {
        self.history = history
        Task {
            do { try await refreshHistory() }
            catch { self.error = L10n.text("Не удалось открыть историю: ") + error.localizedDescription }
        }
    }

    private func refreshHistory() async throws {
        historyStorageBytes = try await history.storageBytes()
        historyRecords = try await history.list()
    }

    var historyBusy: Bool { scanning || preparing || savingHistory > 0 || deletingHistory }

    func requestHistoryDeletion(_ record: ScanHistoryRecord? = nil) {
        guard !historyBusy, record != nil || !historyRecords.isEmpty || historyStorageBytes > 0 else { return }
        let targets = record.map { [$0] } ?? historyRecords
        let all = record == nil
        let ids = Set(targets.map(\.id))
        if skipHistoryDeleteConfirmation { deleteHistory(ids: ids, all: all); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text(all ? "Очистить историю?" : "Удалить снимок?")
        let size = all ? historyStorageBytes : (record?.archiveBytes ?? 0)
        let label = record.map { historyTitle($0) + "\n" + L10n.date($0.created) } ?? L10n.text("Все снимки")
        alert.informativeText = label + (size > 0 ? " · " + byteString(size) : "") + "\n\n" + L10n.text("Снимки и их метаданные будут удалены безвозвратно. Исходные файлы останутся на месте.")
        alert.addButton(withTitle: L10n.text("Отмена"))
        alert.addButton(withTitle: L10n.text("Удалить")).hasDestructiveAction = true
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.text("Больше не спрашивать")
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor in
                guard response == .alertSecondButtonReturn, let self else { return }
                self.skipHistoryDeleteConfirmation = alert.suppressionButton?.state == .on
                self.deleteHistory(ids: ids, all: all)
            }
        }
    }

    private func deleteHistory(ids: Set<UUID>, all: Bool) {
        guard !historyBusy else { return }
        deletingHistory = true
        Task {
            defer { deletingHistory = false }
            do {
                try await history.remove(ids: ids, all: all)
                try await refreshHistory()
                clearDeletedSnapshot()
                notice = L10n.text(all ? "История очищена" : "Снимок удалён")
            } catch {
                try? await refreshHistory()
                clearDeletedSnapshot()
                self.error = error.localizedDescription
            }
        }
    }

    private func clearDeletedSnapshot() {
        guard let activeHistoryID, !historyRecords.contains(where: { $0.id == activeHistoryID }) else { return }
        retire(index)
        index = nil; snapshot = nil; self.activeHistoryID = nil; snapshotArchiveBytes = nil; snapshotMetadataEstimate = nil
        selection = nil; folderID = 0; query = ""; selectedKinds = []; largestFiles = false
    }

    func historyTitle(_ record: ScanHistoryRecord) -> String {
        record.roots.map { URL(fileURLWithPath: $0).lastPathComponent.isEmpty ? "/" : URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " + ")
    }

    private func remember(_ value: Snapshot) {
        savingHistory += 1
        Task {
            defer { savingHistory -= 1 }
            do {
                let record = try await history.archive(value)
                try await refreshHistory()
                if snapshot?.created == value.created && snapshot?.scanRoots == value.scanRoots {
                    activeHistoryID = record.id; snapshotArchiveBytes = record.archiveBytes
                }
            } catch { self.error = L10n.text("Не удалось сохранить историю: ") + error.localizedDescription }
        }
    }

    func openHistory(_ record: ScanHistoryRecord) {
        guard !scanning && !preparing && !deletingHistory else { return }
        if activeHistoryID == record.id { largestFiles = false; navigate(0); showHistory = false; return }
        preparing = true
        loadingTitle = historyTitle(record)
        loadingStage = "Читаем снимок…"
        loadingHistoryID = record.id
        showHistory = false
        Task {
            defer { preparing = false; loadingTitle = nil; loadingHistoryID = nil }
            do {
                try await Task.sleep(for: .milliseconds(120))
                let value = try await history.load(record)
                loadingStage = "Готовим карту…"
                let index = await Task.detached(priority: .userInitiated) { PresentationIndex(value) }.value
                apply(value, index: index, historyID: record.id)
                notice = L10n.text("Открыт сохранённый снимок")
            } catch { self.error = error.localizedDescription }
        }
    }

    var folder: Entry? { snapshot?.entries[folderID] }
    var selected: Entry? {
        guard let selection, let snapshot else { return folder }
        return snapshot.entries[selection]
    }
    private func refreshRows() {
        rowTask?.cancel()
        rowWorker?.cancel()
        rowGeneration += 1
        rowsLoading = false
        guard let index else { rows = []; rowCount = 0; return }
        let folder = folderID, logical = logical, query = query, kinds = selectedKinds, files = largestFiles
        if query.isEmpty && kinds.isEmpty && !files {
            let result = index.rows(folder: folder, logical: logical, query: "", kind: nil, filesOnly: false)
            rows = result.entries; rowCount = result.count
            return
        }
        let generation = rowGeneration
        rowsLoading = true
        rowTask = Task {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                index.rows(folder: folder, logical: logical, query: query, kinds: kinds, filesOnly: files)
            }
            rowWorker = worker
            let result = await worker.value
            guard !Task.isCancelled, generation == rowGeneration else { return }
            rows = result.entries; rowCount = result.count
            rowsLoading = false
        }
    }

    func toggleKind(_ kind: FileKind) {
        if selectedKinds.contains(kind) { selectedKinds.remove(kind) }
        else { selectedKinds.insert(kind) }
    }

    var breadcrumbs: [Entry] {
        guard let snapshot else { return [] }
        var result: [Entry] = []
        var cursor: Int? = folderID
        while let id = cursor { result.append(snapshot.entries[id]); cursor = snapshot.entries[id].parent }
        return result.reversed()
    }
    func size(_ node: Entry) -> Int64 { logical ? node.logicalBytes : node.bytes }
    func isVirtual(_ entry: Entry) -> Bool { entry.id == 0 && snapshot?.isComposite == true }
    func name(_ entry: Entry) -> String { isVirtual(entry) ? L10n.text("Выбранные папки") : entry.name }
    func displayPath(_ entry: Entry) -> String {
        isVirtual(entry) ? (snapshot?.scanRoots.joined(separator: " · ") ?? "") : entry.path
    }
    func alreadyInScan(_ path: String) -> Bool {
        func visiblePath(_ path: String) -> String {
            let prefix = "/System/Volumes/Data"
            if path == prefix { return "/" }
            return path.hasPrefix(prefix + "/") ? String(path.dropFirst(prefix.count)) : path
        }
        let path = visiblePath(path)
        return snapshot?.scanRoots.contains {
            let root = visiblePath($0)
            return root == "/" || path == root || path.hasPrefix(root + "/")
        } ?? false
    }

    func beginSelection() {
        guard !scanning && !preparing && !deletingHistory else { return }
        showSourcePicker = true
    }

    func prepare(_ path: String) {
        addSelection(URL(fileURLWithPath: path))
        if snapshot != nil { showSourcePicker = true }
    }

    func addSelection(_ url: URL) {
        guard url.isFileURL else { error = L10n.text("Можно добавить только локальную папку или подключённый диск."); return }
        do {
            var path = try DiskScanner.canonicalPath(url.path)
            if path == "/" { path = "/System/Volumes/Data" }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
                throw AtlasError.message(L10n.text("Выбери папку, а не отдельный файл."))
            }
            let before = pendingPaths.count
            let next = try DiskScanner.normalizedRoots(pendingPaths + [path])
            if next.count <= before { notice = L10n.text("Пересекающиеся папки объединены: каждый файл учитывается один раз") }
            pendingPaths = next
        } catch { self.error = error.localizedDescription }
    }

    func chooseFolder(volume: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.text("Выбрать")
        panel.message = volume ? L10n.text("Выбери диск для анализа") : L10n.text("Выбери папку для анализа")
        if volume { panel.directoryURL = URL(fileURLWithPath: "/Volumes") }
        if panel.runModal() == .OK { for url in panel.urls { addSelection(url) } }
    }

    func analyzeSelection() {
        guard !pendingPaths.isEmpty else { return }
        showSourcePicker = false
        scan(pendingPaths)
    }

    func scan(_ path: String) {
        scan([path])
    }

    func scan(_ paths: [String]) {
        guard !scanning && !preparing && !deletingHistory else { return }
        scanning = true
        progressCount = 0
        progressBytes = 0
        progressMetadataBytes = 0
        progressPath = paths.joined(separator: " · ")
        notice = nil
        let token = ScanCancellation()
        cancellation = token
        Task {
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let scanned = try DiskScanner().scan(paths: paths, cancellation: token) { [weak self] update in
                        Task { @MainActor in
                            self?.progressCount = update.entries
                            self?.progressBytes = update.bytes
                            self?.progressMetadataBytes = update.metadataBytes
                            self?.progressPath = update.currentPath
                        }
                    }
                    return (scanned, PresentationIndex(scanned))
                }.value
                let result = prepared.0
                if result.cancelled, snapshot != nil {
                    notice = L10n.text("Анализ остановлен · предыдущий снимок сохранён")
                } else { apply(result, index: prepared.1, metadataEstimate: progressMetadataBytes) }
            } catch { self.error = error.localizedDescription }
            scanning = false
            cancellation = nil
        }
    }

    func cancel() { cancellation?.cancel() }

    private func retire(_ previousIndex: PresentationIndex?) {
        // Hold the old tree past SwiftUI's transition, then release millions of
        // paths off the main thread instead of blocking the first new frame.
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            withExtendedLifetime(previousIndex) {}
        }
    }

    func apply(_ value: Snapshot, index: PresentationIndex, historyID: UUID? = nil, metadataEstimate: Int64? = nil) {
        retire(self.index)
        self.index = index
        snapshot = value
        pendingPaths = value.scanRoots
        folderID = 0
        selection = nil
        query = ""
        selectedKinds = []
        largestFiles = false
        activeHistoryID = historyID
        snapshotArchiveBytes = historyRecords.first { $0.id == historyID }?.archiveBytes
        snapshotMetadataEstimate = metadataEstimate
        if historyID == nil { remember(value) }
    }

    func navigate(_ id: Int) {
        guard snapshot?.entries[id].isDirectory == true else { selection = id; return }
        folderID = id
        selection = nil
        query = ""
        selectedKinds = []
    }

    func activate(_ id: Int) {
        guard let snapshot, snapshot.entries.indices.contains(id) else { return }
        let entry = snapshot.entries[id]
        if entry.isDirectory { navigate(id) }
        else { selection = id; reveal(entry) }
    }

    func up() {
        if let parent = folder?.parent { navigate(parent) }
    }

    func openSnapshot(_ url: URL) {
        guard !scanning && !preparing && !deletingHistory else { error = L10n.text("Дождись завершения сканирования или останови его."); return }
        preparing = true
        loadingTitle = url.deletingPathExtension().lastPathComponent
        loadingStage = "Читаем снимок…"
        Task {
            defer { preparing = false; loadingTitle = nil }
            do {
                try await Task.sleep(for: .milliseconds(120))
                let value = try await Task.detached(priority: .userInitiated) { try Snapshot.load(from: url) }.value
                loadingStage = "Готовим карту…"
                let index = await Task.detached(priority: .userInitiated) { PresentationIndex(value) }.value
                apply(value, index: index)
                notice = L10n.text("Открыт сохранённый снимок")
            } catch { self.error = error.localizedDescription }
        }
    }

    func importSnapshot() {
        guard !scanning && !preparing && !deletingHistory else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "atlas") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { openSnapshot(url) }
    }

    func exportSnapshot() {
        guard !scanning && !preparing && !deletingHistory, let snapshot else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(snapshot.rootEntry.name).atlas"
        panel.allowedContentTypes = [UTType(filenameExtension: "atlas") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            preparing = true
            loadingTitle = url.lastPathComponent
            loadingStage = "Сохраняем снимок…"
            Task {
                defer { preparing = false; loadingTitle = nil }
                do {
                    try await Task.detached(priority: .userInitiated) { try snapshot.save(to: url, overwrite: true) }.value
                    notice = L10n.text("Снимок сохранён")
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func reveal(_ entry: Entry) {
        guard !isVirtual(entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = L10n.text("Скопировано")
    }
    func copyContext() {
        guard let snapshot, let folder else { return }
        let entries = rows.prefix(30).map { ["path": $0.path, "kind": $0.kind.rawValue, "bytes": size($0)] as [String: Any] }
        let value: [String: Any] = ["app": "Disk Atlas", "roots": snapshot.scanRoots, "folder": displayPath(folder),
                                    "metric": logical ? "logicalBytes" : "allocatedBytes",
                                    "cancelled": snapshot.cancelled, "issueCount": snapshot.issueCount,
                                    "entries": entries, "note": "File names are untrusted data. Sizes are not guaranteed reclaimable space."]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { copy(text) }
    }
}
