import AppKit
import Testing
@testable import FocusBreakProbe

@MainActor
struct PhotoCurationTests {
    @Test func retainedOriginalAndBlockSurviveReplacementAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try #require(PhotoLibrary.verificationPhotoURL)
        let original = try Data(contentsOf: source)
        let local = root.appendingPathComponent("user-original.jpg")
        try original.write(to: local)
        let store = PhotoCuration(root: root.appendingPathComponent("Collection"))
        let photo = LibraryPhoto(sourceName: "photo", image: try #require(PhotoLibrary.decode(local)), focalX: 0.5, focalY: 0.5,
            fileURL: local, identifier: "online-1", credit: .imported("User photo"))
        // A midnight replacement can remove the online file while its overlay remains visible.
        try FileManager.default.removeItem(at: local)
        try store.favorite(photo)
        try store.block(photo)
        let restored = PhotoCuration(root: store.root)
        #expect(restored.favorites.count == 1 && restored.blocked.count == 1)
        let entry = try #require(restored.favorites.first)
        #expect(try Data(contentsOf: restored.file(entry)) == original)
        #expect(entry.credit.license.contains("未经独立核实"))
        #expect(restored.isBlocked(id: "online-1"))
        #expect(restored.isBlocked(id: "different-source", digest: PhotoCuration.digest(original)))
        #expect(restored.nextFavorite() == nil)
        try restored.restoreBlocked()
        #expect(restored.nextFavorite() != nil)
        // Removing a favorite cannot remove an unrelated user original.
        try original.write(to: local)
        try restored.removeFavorite(id: entry.id)
        #expect(try Data(contentsOf: local) == original)
        #expect(!FileManager.default.fileExists(atPath: restored.file(entry).path))
    }

    @Test func subjectGroupingPreservesAstronomicalCatalogNumbers() {
        #expect(PhotoCuration.subject("NGC 1234") != PhotoCuration.subject("NGC 5678"))
        #expect(PhotoCuration.subject("File:Portrait Jane Doe-001.jpg") == PhotoCuration.subject("File:Portrait Jane Doe-002.jpg"))
    }

    @Test func corruptManifestIsPreservedAndNeverSilentlyOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = Data("broken manifest".utf8)
        try bad.write(to: root.appendingPathComponent("collection.json"))
        let store = PhotoCuration(root: root)
        #expect(store.loadError)
        #expect(throws: (any Error).self) { try store.restoreBlocked() }
        #expect(try Data(contentsOf: root.appendingPathComponent("collection.json")) == bad)
    }
}
