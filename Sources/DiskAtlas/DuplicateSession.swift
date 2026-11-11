import AtlasCore
import SwiftUI

@MainActor final class DuplicateSession: ObservableObject {
    @Published var options = DuplicateOptions()
    @Published var resultFilter = DuplicateOptions() {
        didSet {
            focusedGroupID = nil
            trashSelection = DuplicateTrashSelection()
            refreshOrder()
        }
    }
    var hasResultContext: Bool { report != nil || running }
    var resultFilterActive: Bool { resultFilter != DuplicateOptions() }
    var limitedCoverage: Bool {
        report.map { !$0.options.covers(resultFilter) || $0.cancelled || $0.inputPartial == true } ?? false
    }
    var canFilterResults: Bool { !loadingReport && !trashPreparing && !trashing }

    @Published private(set) var busy = false { didSet { if !busy { stopping = false } } }
    @Published private(set) var stopping = false
    @Published private(set) var running = false
    @Published private(set) var preparing = false
    @Published private(set) var loadingReport = false
    @Published private(set) var savingReport = false
    @Published private(set) var paused = false
    @Published private(set) var foregroundPaused = false
    @Published private(set) var progress = DuplicateProgress()
    @Published private(set) var plan: DuplicatePlan?
    @Published private(set) var report: DuplicateReport?
    @Published private(set) var groups: [DuplicateGroup] = [] { didSet { refreshOrder() } }
    @Published private(set) var orderedGroups: [DuplicateGroup] = []
    @Published private(set) var sorting = false
    @Published var search = "" {
        didSet {
            focusedGroupID = nil
            refreshOrder(debounce: true)
        }
    }
    private var resultLimit = 500
    var hasMoreResults: Bool { orderedGroups.count < orderedCount }
    func loadMoreResults() {
        guard !sorting, hasMoreResults else { return }
        resultLimit += 500
        refreshOrder(resetLimit: false)
    }
    @Published private(set) var orderedCount = 0
    @Published private(set) var orderedRepeatedBytes: Int64 = 0
    @Published var sort: DuplicateSort = .repeatedBytes { didSet { refreshOrder() } }
    @Published var sortDescending = true { didSet { refreshOrder() } }
    private var orderTask: Task<Void, Never>?
    private var orderWorker: Task<DuplicateResultPage, Error>?
    private var orderGeneration = 0
    @Published private(set) var metadataBytes: Int64 = 0
    @Published private(set) var roots: [String] = []
    @Published private(set) var snapshotCreated: Date?
    @Published private(set) var lookup: DuplicateLookup?
    @Published var focusedGroupID: String?
    @Published var error: String?
    private(set) var ownerID: UUID?
    @Published var trashSelection = DuplicateTrashSelection()
    @Published var trashReview: DuplicateTrashPlan?
    @Published private(set) var trashPreparing = false
    @Published private(set) var trashing = false
    @Published private(set) var trashProgress = DuplicateTrashProgress()
    @Published private(set) var trashMovedCount: Int?
    var trashNotice: String? {
        guard let trashMovedCount else { return nil }
        return L10n.text("В корзине: ") + String(trashMovedCount) + ". "
            + L10n.text("Обнови анализ для актуальных размеров.")
    }
    @Published var scopePath: String? { didSet { refreshOrder() } }
    private var trashControl: DuplicateControl?
    private let history: ScanHistory
    private var task: Task<Void, Never>?
    private var worker: Task<DuplicatePlan, Error>?
    private var lookupWorker: Task<DuplicateLookup, Error>?
    private var exportWorker: Task<Void, Error>?
    private var control: DuplicateControl?
    private var generation = UUID()
    init(history: ScanHistory) { self.history = history }

    var title: String { roots.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " + ") }
    var phaseTitle: String {
        if stopping { return L10n.text("Останавливаем…") }
        if let title = preparationTitle { return title }
        if let title = activityTitle { return title }
        switch progress.phase {
        case .preparing: return L10n.text("Отбираем кандидатов…")
        case .sampling: return L10n.text("Проверяем начало и конец…")
        case .hashing: return L10n.text("Сравниваем содержимое…")
        case .verifying: return L10n.text("Подтверждаем совпадения…")
        case .finished:
            return L10n.text(report?.cancelled == true ? "Остановлено · неполный результат" : "Проверка завершена")
        }
    }
    private var preparationTitle: String? {
        if trashPreparing { return L10n.text("Готовим список…") }
        if trashing {
            return L10n.text(trashProgress.stage == .verifying ? "Проверяем копии…" : "Перемещаем в Корзину…")
        }
        if savingReport { return L10n.text("Сохраняем отчёт…") }
        if loadingReport { return L10n.text("Загружаем отчёт…") }
        return nil
    }
    private var activityTitle: String? {
        if foregroundPaused { return L10n.text("Пауза · основной анализ") }
        if running && progress.phase == .finished { return L10n.text("Сохраняем отчёт…") }
        if paused { return L10n.text("Приостановлено") }
        return nil
    }
    var canChangeOptions: Bool { !running && !loadingReport && !savingReport && !trashing && !trashPreparing }
    var fraction: Double {
        progress.phaseTotal > 0 ? min(1, Double(progress.phaseBytes) / Double(progress.phaseTotal)) : 0
    }
    var estimate: String {
        guard let plan else { return L10n.text("Оценка появится после подготовки") }
        guard plan.candidateCount > 0 else { return L10n.text("Нет кандидатов для сравнения") }
        // An honest broad planning range, never a claimed hardware benchmark.
        return Self.duration(
            Double(plan.estimatedReadBytes) / 250_000_000 + Double(plan.candidateCount) * 0.0005,
            Double(plan.estimatedReadBytes) / 25_000_000 + Double(plan.candidateCount) * 0.03)
    }
    var remaining: String? {
        guard progress.activeSeconds >= 2, progress.phaseBytes > 0, progress.phaseTotal > progress.phaseBytes else {
            return nil
        }
        let speed = Double(progress.readBytes) / max(1, progress.activeSeconds)
        let phaseLeft = Double(progress.phaseTotal - progress.phaseBytes)
        let extra = Double(progress.futureReadBytes)
        return Self.duration(
            (phaseLeft + extra * 0.25) / max(1, speed) * 0.8, (phaseLeft + extra) / max(1, speed) * 1.3)
    }
    static func duration(_ low: Double, _ high: Double) -> String {
        if high < 60 { return L10n.text("менее минуты") }
        let a = max(1, Int(ceil(low / 60)))
        let b = max(a, Int(ceil(high / 60)))
        if b >= 120 { return "≈ \(max(1, a / 60))–\(max(2, Int(ceil(Double(b) / 60)))) " + L10n.text("ч") }
        return "≈ \(a)–\(b) " + L10n.text("мин")
    }

    func select(_ snapshot: Snapshot, id: UUID?, prepareIfMissing: Bool = false) {
        guard !busy else { return }
        generation = UUID()
        let key = generation
        task?.cancel()
        worker?.cancel()
        clearTrashSelection()
        roots = snapshot.scanRoots
        snapshotCreated = snapshot.created
        ownerID = id
        retireResults()
        plan = nil
        report = nil
        groups = []
        lookup = nil
        focusedGroupID = nil
        metadataBytes = 0
        error = nil
        progress = DuplicateProgress()
        guard let id else { return }
        busy = true
        loadingReport = true
        task = Task {
            defer {
                if generation == key {
                    busy = false
                    loadingReport = false
                }
            }
            do {
                let saved = try await history.loadDuplicates(id: id)
                guard generation == key, !Task.isCancelled else { return }
                if let saved {
                    let lookup = try await buildLookup(saved.0)
                    guard generation == key, !Task.isCancelled else { return }
                    self.lookup = lookup
                    report = saved.0
                    groups = saved.0.groups
                    options = saved.0.options
                    metadataBytes = saved.1
                    progress.phase = .finished
                } else if prepareIfMissing {
                    prepare(snapshot, id: id)
                }
            } catch { if generation == key { self.error = error.localizedDescription } }
        }
    }
    func attach(_ id: UUID, to snapshot: Snapshot) {
        guard snapshotCreated == snapshot.created && roots == snapshot.scanRoots else { return }
        ownerID = id
        // A tiny check can finish before its scan archive. Persist it once the owner exists.
        if let report, !busy {
            busy = true
            savingReport = true
            task = Task {
                defer {
                    busy = false
                    savingReport = false
                }
                do { metadataBytes = try await history.saveDuplicates(report, id: id) } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func prepare(_ snapshot: Snapshot, id: UUID?, debounce: Bool = false, autoStart: Bool = false) {
        guard !running && !savingReport && !trashing && !trashPreparing else { return }
        task?.cancel()
        worker?.cancel()
        control?.cancel()
        generation = UUID()
        let key = generation
        var settings = options
        settings.modifiedAfter = nil
        settings.modifiedBefore = nil
        options = settings
        clearTrashSelection()
        roots = snapshot.scanRoots
        snapshotCreated = snapshot.created
        ownerID = id
        retireResults()
        plan = nil
        report = nil
        groups = []
        lookup = nil
        focusedGroupID = nil
        metadataBytes = 0
        error = nil
        loadingReport = false
        busy = true
        preparing = true
        progress = DuplicateProgress()
        let token = DuplicateControl()
        control = token
        task = Task {
            await preparePlan(
                snapshot, settings: settings, key: key, token: token, debounce: debounce, autoStart: autoStart)
        }
    }
    private func preparePlan(
        _ snapshot: Snapshot, settings: DuplicateOptions, key: UUID, token: DuplicateControl, debounce: Bool,
        autoStart: Bool
    ) async {
        defer {
            if generation == key {
                busy = false
                preparing = false
                control = nil
            }
        }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(350)) }
            try Task.checkCancellation()
            let job = Task.detached(priority: .utility) {
                try DuplicateFinder().prepare(snapshot, options: settings, control: token) { [weak self] update in
                    Task { @MainActor in if self?.generation == key { self?.progress = update } }
                }
            }
            worker = job
            let result = try await job.value
            acceptPlan(result, key: key, autoStart: autoStart)
        } catch is CancellationError {} catch {
            if generation == key {
                AppDiagnostics.shared.failed(.duplicatePreparationFailed)
                self.error = error.localizedDescription
            }
        }
    }
    private func acceptPlan(_ result: DuplicatePlan, key: UUID, autoStart: Bool) {
        guard generation == key, !Task.isCancelled else { return }
        plan = result
        if autoStart && result.candidateCount > 0 {
            preparing = false
            busy = false
            control = nil
            start()
        }
    }
    func start() {
        guard let plan, !busy, plan.candidateCount > 0 else { return }
        generation = UUID()
        let key = generation
        let token = DuplicateControl()
        control = token
        busy = true
        running = true
        paused = false
        foregroundPaused = false
        report = nil
        groups = []
        error = nil
        progress = DuplicateProgress()
        progress.phase = .hashing
        task = Task {
            defer {
                busy = false
                running = false
                paused = false
                foregroundPaused = false
                savingReport = false
                control = nil
            }
            do {
                let result = try await Task.detached(priority: .utility) {
                    try DuplicateFinder().run(
                        plan, control: token,
                        progress: { [weak self] update in
                            Task { @MainActor in if self?.generation == key { self?.progress = update } }
                        }, found: { [weak self] group in Task { @MainActor in self?.receive(group, generation: key) } })
                }.value
                AppDiagnostics.shared.completed(
                    .duplicates, seconds: result.elapsed, objects: plan.candidateCount, cancelled: result.cancelled)
                try await finish(result)
            } catch is CancellationError { error = L10n.text("Сохранение отменено.") } catch {
                AppDiagnostics.shared.failed(.duplicateCheckFailed)
                self.error = error.localizedDescription
            }
        }
    }
    private func receive(_ batch: [DuplicateGroup], generation key: UUID) {
        guard generation == key, report == nil else { return }
        groups.append(contentsOf: batch)
    }
    private func buildLookup(_ report: DuplicateReport) async throws -> DuplicateLookup {
        let job = Task.detached(priority: .utility) { try DuplicateLookup(report) }
        lookupWorker = job
        defer { lookupWorker = nil }
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }
    private func finish(_ result: DuplicateReport) async throws {
        running = false
        paused = false
        foregroundPaused = false
        savingReport = true
        retireResults()
        report = result
        groups = result.groups
        lookup = try await buildLookup(result)
        try Task.checkCancellation()
        if let ownerID { metadataBytes = try await history.saveDuplicates(result, id: ownerID) }
    }
    func togglePause() {
        guard running else { return }
        paused.toggle()
        control?.pause(paused)
    }
    func foreground(_ busy: Bool) {
        guard running || preparing, foregroundPaused != busy else { return }
        foregroundPaused = busy
        control?.pause(busy, foreground: true)
    }
    func stop() {
        if busy { stopping = true }
        if trashPreparing || savingReport { task?.cancel() }
        lookupWorker?.cancel()
        exportWorker?.cancel()
        trashControl?.cancel()
        control?.cancel()
        if preparing || loadingReport {
            worker?.cancel()
            task?.cancel()
        }
    }
    private func retireResults() {
        let oldPlan = plan
        let oldReport = report
        let oldGroups = groups
        let oldLookup = lookup
        Task.detached(priority: .utility) { withExtendedLifetime((oldPlan, oldReport, oldGroups, oldLookup)) {} }
    }
    func discard() {
        guard !busy else { return }
        generation = UUID()
        task?.cancel()
        worker?.cancel()
        retireResults()
        clearTrashSelection()
        plan = nil
        report = nil
        groups = []
        lookup = nil
        focusedGroupID = nil
        roots = []
        snapshotCreated = nil
        ownerID = nil
        metadataBytes = 0
    }
    func sortBy(_ key: DuplicateSort) {
        if sort == key {
            sortDescending.toggle()
        } else {
            sortDescending = key != .name
            sort = key
        }
    }
    private func refreshOrder(resetLimit: Bool = true, debounce: Bool = false) {
        if resetLimit { resultLimit = 500 }
        orderTask?.cancel()
        orderWorker?.cancel()
        orderGeneration &+= 1
        guard !groups.isEmpty else {
            orderedGroups = []
            orderedCount = 0
            orderedRepeatedBytes = 0
            sorting = false
            return
        }
        let generation = orderGeneration
        let values = groups
        let key = sort
        let filters = resultFilter
        let search = search
        let limit = resultLimit
        let scope = scopePath
        let lookup = lookup
        let descending = sortDescending
        sorting = true
        orderTask = Task {
            do {
                if debounce { try await Task.sleep(for: .milliseconds(120)) }
                let worker = Task.detached(priority: .userInitiated) {
                    let index = try lookup?.results ?? DuplicateResultIndex(values)
                    return try index.query(
                        options: filters, scope: scope, sort: key, descending: descending, limit: limit, search: search)
                }
                orderWorker = worker
                let ordered = try await worker.value
                guard !Task.isCancelled, orderGeneration == generation else { return }
                orderedGroups = ordered.groups
                orderedCount = ordered.count
                orderedRepeatedBytes = ordered.repeatedBytes
                sorting = false
            } catch is CancellationError {} catch {
                if orderGeneration == generation {
                    self.error = error.localizedDescription
                    sorting = false
                }
            }
        }
    }
    func reveal(_ file: DuplicateFile) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }
    private func clearTrashSelection() {
        trashSelection = DuplicateTrashSelection()
        search = ""
        resultFilter = DuplicateOptions()
        trashReview = nil
        trashMovedCount = nil
        scopePath = nil
    }
    func reviewTrash(_ paths: Set<String>? = nil) {
        guard !busy, let report else { return }
        let selected = paths ?? trashSelection.paths
        busy = true
        trashPreparing = true
        error = nil
        task = Task {
            defer {
                busy = false
                trashPreparing = false
            }
            do {
                let plan = try await Task.detached(priority: .userInitiated) {
                    try DuplicateTrashPlan(report: report, paths: selected)
                }.value
                if !Task.isCancelled { trashReview = plan }
            } catch { self.error = error.localizedDescription }
        }
    }
    func reviewTrash(_ group: DuplicateGroup) {
        let selected = Set(group.files.map(\.path)).intersection(trashSelection.paths)
        reviewTrash(selected.isEmpty ? Set(group.files.map(\.path)) : selected)
    }
    func trash(_ plan: DuplicateTrashPlan) {
        guard !busy, let report, report.checkedAt == plan.checkedAt, report.snapshotCreated == plan.snapshotCreated
        else { return }
        trashReview = nil
        busy = true
        trashing = true
        trashProgress = DuplicateTrashProgress()
        trashMovedCount = nil
        error = nil
        let control = DuplicateControl()
        trashControl = control
        task = Task {
            defer {
                busy = false
                trashing = false
                trashControl = nil
            }
            let outcome = await Task.detached(priority: .utility) {
                DuplicateTrashExecutor.run(plan, control: control) { [weak self] progress in
                    Task { @MainActor in self?.trashProgress = progress }
                }
            }.value
            await applyTrash(outcome, to: report)
        }
    }
    private func applyTrash(_ outcome: DuplicateTrashOutcome, to original: DuplicateReport) async {
        if !outcome.moved.isEmpty {
            let updated = await Task.detached(priority: .utility) { original.removing(outcome.moved) }.value
            retireResults()
            report = updated
            lookup = try? await buildLookup(updated)
            groups = updated.groups
            trashSelection = DuplicateTrashSelection()
            trashMovedCount = outcome.moved.count
            if let ownerID {
                do { metadataBytes = try await history.saveDuplicates(updated, id: ownerID) } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        if let error = outcome.error { self.error = error }
        if outcome.cancelled { self.error = L10n.text("Остановлено. Уже перемещённые файлы находятся в Корзине.") }
    }
    func reconcileRemovedPaths(_ paths: Set<String>) {
        guard !busy, let report else {
            discard()
            return
        }
        busy = true
        savingReport = true
        task = Task {
            defer {
                busy = false
                savingReport = false
            }
            let removed = await Task.detached(priority: .utility) {
                Set(
                    report.groups.flatMap(\.files).map(\.path).filter { file in
                        paths.contains(file) || paths.contains { file.hasPrefix($0 + "/") }
                    })
            }.value
            await applyTrash(DuplicateTrashOutcome(moved: removed), to: report)
        }
    }
    func export() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duplicates.json"
        if panel.runModal() == .OK, let url = panel.url {
            busy = true
            savingReport = true
            task = Task {
                defer {
                    busy = false
                    savingReport = false
                }
                do {
                    let job = Task.detached(priority: .utility) {
                        let data = try Snapshot.encoder.encode(report)
                        try Task.checkCancellation()
                        try data.write(to: url, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    }
                    exportWorker = job
                    defer { exportWorker = nil }
                    try await withTaskCancellationHandler {
                        try await job.value
                    } onCancel: {
                        job.cancel()
                    }
                } catch is CancellationError { error = L10n.text("Сохранение отменено.") } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
