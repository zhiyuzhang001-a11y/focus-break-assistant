import Foundation
import Darwin

/// Serializes app and diagnostic updates to the same on-disk reservoir.
final class ReservoirFileLock {
    private var descriptor: Int32 = -1
    func acquire(root: URL) throws -> Bool {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        descriptor = Darwin.open(root.appendingPathComponent(".update.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
    func release() { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } }
    deinit { release() }
}
