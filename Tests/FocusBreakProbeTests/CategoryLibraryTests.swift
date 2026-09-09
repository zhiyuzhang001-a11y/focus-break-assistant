import AppKit
import Testing
import FocusBreakProbeCore
@testable import FocusBreakProbe

@MainActor
struct CategoryLibraryTests {
    @Test func importIsIsolatedAndRoundAvoidsBoundaryRepeat() throws {
        let suite = "CategoryLibraryTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let library = CategoryLibrary(defaults: defaults, root: root)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let first = repo.appendingPathComponent("Sources/FocusBreakProbe/Resources/Seascape.jpg")
        let second = repo.appendingPathComponent("Sources/FocusBreakProbe/Resources/AlpineLake.jpg")
        let original = try Data(contentsOf: first)
        let result = library.importFiles([first, second], category: .space)
        #expect(result.success == 2)
        #expect(library.localFiles(.space).count == 2)
        #expect(library.localFiles(.people).isEmpty)
        #expect(library.importFiles([first], category: .space).success == 1)
        #expect(library.localFiles(.space).count == 2)
        #expect(try Data(contentsOf: first) == original)
        library.preferences.categories = [.space]
        let one = library.nextPhoto()?.sourceName
        let two = library.nextPhoto()?.sourceName
        #expect(one != nil && two != nil && one != two)
        let restored = CategoryLibrary(defaults: defaults, root: root)
        #expect(restored.nextPhoto()?.sourceName != two)
        library.preferences.categories = [.cartoon]
        #expect(library.nextPhoto() == nil)
        for file in library.localFiles(.space) { try FileManager.default.removeItem(at: file) }
        library.preferences.categories = [.space]
        #expect(library.nextPhoto() == nil)
    }
}
