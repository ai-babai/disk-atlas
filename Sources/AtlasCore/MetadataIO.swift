import Darwin
import Foundation

/// Keep metadata traversal from hydrating cloud directories. Never suspend inside this thread-local scope.
enum MetadataIO {
    static func withoutCloudDownloads<T>(_ body: () throws -> T) throws -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let scope = IOPOL_SCOPE_THREAD
        let previous = getiopolicy_np(type, scope)
        guard previous >= 0, setiopolicy_np(type, scope, IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0 else {
            throw AtlasError.message("Не удалось запретить загрузку облачных файлов. Анализ остановлен.")
        }
        defer { setiopolicy_np(type, scope, previous) }
        return try body()
    }
}
