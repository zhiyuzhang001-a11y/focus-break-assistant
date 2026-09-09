import Foundation
import Darwin

final class ApplicationInstance {
    private var descriptor: Int32 = -1
    func acquire() throws -> Bool {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = Darwin.open(directory.appendingPathComponent("application.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}
