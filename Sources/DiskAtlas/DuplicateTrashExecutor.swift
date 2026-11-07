import AtlasCore
import Foundation

struct DuplicateTrashProgress: Sendable {
    enum Stage: Sendable { case verifying, moving }
    var stage: Stage = .verifying
    var completed: Int64 = 0
    var total: Int64 = 0
}
struct DuplicateTrashOutcome: Sendable {
    var moved = Set<String>()
    var error: String?
    var cancelled = false
}

enum DuplicateTrashExecutor {
    static func run(
        _ plan: DuplicateTrashPlan, control: DuplicateControl,
        progress: @escaping @Sendable (DuplicateTrashProgress) -> Void,
        move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> DuplicateTrashOutcome {
        var result = DuplicateTrashOutcome()
        do {
            try verify(plan, control: control, progress: progress)
            try moveFiles(plan, control: control, progress: progress, moved: &result.moved, move: move)
        } catch is CancellationError { result.cancelled = true } catch { result.error = error.localizedDescription }
        return result
    }
    private static func verify(
        _ plan: DuplicateTrashPlan, control: DuplicateControl,
        progress: @escaping @Sendable (DuplicateTrashProgress) -> Void
    ) throws {
        var value = DuplicateTrashProgress(total: plan.verificationBytes)
        var last = Date.distantPast
        progress(value)
        for batch in plan.batches {
            for file in batch.files where file.path != batch.reference.path {
                let equal = try DuplicateFinder().confirm(file, matches: batch.reference, control: control) { count in
                    value.completed += Int64(count)
                    if Date().timeIntervalSince(last) > 0.1 {
                        progress(value)
                        last = Date()
                    }
                }
                guard equal else { throw AtlasError.message("Содержимое копий различается. Повтори поиск дубликатов.") }
            }
        }
    }
    private static func moveFiles(
        _ plan: DuplicateTrashPlan, control: DuplicateControl,
        progress: @escaping @Sendable (DuplicateTrashProgress) -> Void, moved: inout Set<String>,
        move: (URL) throws -> Void
    ) throws {
        var value = DuplicateTrashProgress(stage: .moving, total: Int64(plan.files.count))
        progress(value)
        for batch in plan.batches {
            // A comparison reference selected for Trash moves last in its group.
            let ordered =
                batch.files.filter { $0.path != batch.reference.path }
                + batch.files.filter { $0.path == batch.reference.path }
            for file in ordered {
                try control.checkpoint()
                try DuplicateFinder().validate(batch.reference)
                try DuplicateFinder().validate(file)
                try move(URL(fileURLWithPath: file.path))
                moved.insert(file.path)
                value.completed += 1
                progress(value)
            }
        }
    }
}
