import Foundation

/// Filesystem metadata only. Reading capacity never walks directories or reads file contents.
public struct VolumeCapacity: Sendable {
    public let name: String
    public let total: Int64
    public let available: Int64

    public static func read(at url: URL = URL(fileURLWithPath: "/")) throws -> VolumeCapacity {
        let values = try url.resourceValues(forKeys: [.volumeNameKey])
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return VolumeCapacity(name: values.volumeName ?? "Mac", total: max(0, total), available: max(0, available))
    }
}
