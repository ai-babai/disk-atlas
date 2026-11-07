import AtlasCore
import Foundation

@MainActor final class FileTrashSession: ObservableObject {
    @Published var selected = Set<Int>()
    @Published var review: FileTrashPlan?
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var message: String?
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var control: DuplicateControl?
    private(set) var moved = Set<String>()

    func toggle(_ id: Int) {
        guard !busy else { return }
        if selected.remove(id) == nil { selected.insert(id) }
    }
    func toggle(_ ids: Set<Int>) {
        guard !busy else { return }
        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
    }
    func prepare(_ snapshot: Snapshot, ids: Set<Int>? = nil) {
        guard !busy else { return }
        let ids = ids ?? selected
        busy = true
        message = nil
        error = nil
        task = Task {
            defer { busy = false }
            do {
                let job = Task.detached(priority: .utility) { try FileTrashPlan(snapshot: snapshot, selected: ids) }
                let plan = try await job.value
                try Task.checkCancellation()
                review = plan
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func move(_ plan: FileTrashPlan, applied: @escaping (Set<String>) -> Void) {
        guard !busy, review?.id == plan.id else { return }
        review = nil
        busy = true
        completed = 0
        let token = DuplicateControl()
        control = token
        task = Task {
            let result = await Task.detached(priority: .utility) {
                FileTrashExecutor.run(plan, control: token) { [weak self] count in
                    Task { @MainActor in self?.completed = count }
                }
            }.value
            moved.formUnion(result.moved)
            selected = []
            applied(result.moved)
            message =
                L10n.text("В корзине: ") + String(result.moved.count) + ". "
                + L10n.text("Обнови анализ для актуальных размеров.")
            error = result.error
            busy = false
            control = nil
        }
    }
    func stop() {
        task?.cancel()
        control?.cancel()
    }
    func reset() {
        selected = []
        review = nil
        moved = []
        message = nil
    }
}

enum FileTrashExecutor {
    static func run(
        _ plan: FileTrashPlan, control: DuplicateControl, progress: @escaping @Sendable (Int) -> Void,
        move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> DuplicateTrashOutcome {
        var result = DuplicateTrashOutcome()
        do {
            for item in plan.items {
                try control.checkpoint()
                try item.validate()
            }
            for item in plan.items {
                try control.checkpoint()
                try item.validate()
                try move(URL(fileURLWithPath: item.entry.path))
                result.moved.insert(item.entry.path)
                progress(result.moved.count)
            }
        } catch is CancellationError { result.cancelled = true } catch { result.error = error.localizedDescription }
        return result
    }
}
