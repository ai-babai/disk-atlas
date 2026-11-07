import CXXHash
import Foundation

/// A fast candidate fingerprint, never a replacement for byte comparison or file identity checks.
final class ContentFingerprint {
    private let state: OpaquePointer
    init() throws {
        guard let state = XXH3_createState() else { throw AtlasError.message("Не удалось выделить память.") }
        self.state = state
        XXH3_128bits_reset(state)
    }
    deinit { XXH3_freeState(state) }
    func update(_ buffer: UnsafeRawBufferPointer) { XXH3_128bits_update(state, buffer.baseAddress, buffer.count) }
    func finalize() -> String {
        let value = XXH3_128bits_digest(state)
        return "xxh3-128:" + String(format: "%016llx%016llx", value.high64, value.low64)
    }
}
