import Foundation
import Testing
@testable import FocusBreakProbeCore

struct DailyPhotoCacheTests {
    private func temporaryCache() throws -> DailyPhotoCache {
        let cache = DailyPhotoCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try cache.repair()
        return cache
    }
    private func photo(_ id: Int) -> CachedPhoto {
        CachedPhoto(id: id, photographer: "Test", sourceURL: URL(string: "https://www.pexels.com/photo/\(id)/")!, downloadedAt: Date(timeIntervalSince1970: Double(id)))
    }
    @Test func countLimitEvictsOldestAndSurvivesRestart() throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        for id in 1...13 { try cache.insert(Data(repeating: 1, count: 100), photo: photo(id)) }
        #expect(cache.photos().map(\.id) == Array(4...13))
        #expect(DailyPhotoCache(directory: cache.directory).photos() == cache.photos())
    }
    @Test func byteLimitEvictsBeforeWriteAndRejectsOversizedPhoto() throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        for id in 1...8 { try cache.insert(Data(repeating: 1, count: 6 * 1_024 * 1_024), photo: photo(id)) }
        #expect(cache.bytesUsed <= DailyPhotoCache.maximumBytes)
        #expect(cache.photos().map(\.id) == [5, 6, 7, 8])
        #expect(throws: (any Error).self) {
            try cache.insert(Data(repeating: 0, count: DailyPhotoCache.maximumPhotoBytes + 1), photo: photo(9))
        }
        #expect(cache.photos().count == 4)
    }
    @Test func interruptedWriteRepairAndClearPreservePersonalPhotos() throws {
        let cache = try temporaryCache()
        let personal = cache.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([1, 2, 3]).write(to: personal)
        defer { try? FileManager.default.removeItem(at: cache.directory); try? FileManager.default.removeItem(at: personal) }
        try cache.insert(Data([4]), photo: photo(1))
        try Data([5]).write(to: cache.directory.appendingPathComponent("orphan.jpg"))
        try FileManager.default.removeItem(at: cache.directory.appendingPathComponent("pexels-1.jpg"))
        try cache.repair()
        #expect(cache.photos().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: cache.directory.appendingPathComponent("orphan.jpg").path))
        try cache.clear()
        #expect(cache.bytesUsed == 0)
        #expect(try Data(contentsOf: personal) == Data([1, 2, 3]))
    }
}
