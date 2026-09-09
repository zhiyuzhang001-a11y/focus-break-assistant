import AppKit
import Testing
import FocusBreakProbeCore
@testable import FocusBreakProbe

@MainActor
struct OnlineReservoirFailureTests {
    @Test func offlineRefreshPreservesWholeOldBatchAndCleansStage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ReservoirFailure." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var attempts: [ImageCategory] = []
        let online = OnlineReservoir(defaults: defaults, root: root, candidates: { category, _, _ in attempts.append(category); throw URLError(.notConnectedToInternet) })
        let store = online.store
        let stage = try store.begin(.nature)
        let data = try Data(contentsOf: #require(PhotoLibrary.verificationPhotoURL))
        let images = (0..<10).map { index in
            ReservoirImage(id: "old-\(index)", title: "old", author: "test", source: URL(string: "https://example.com/source")!,
                download: URL(string: "https://example.com/image")!, license: "test fixture", licenseURL: URL(string: "https://example.com/license")!, provider: "fixture")
        }
        for image in images { try store.append(data, image: image, stage: stage) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let day = Date(timeIntervalSince1970: 1788782400)
        try store.commit(images, stage: stage, category: .nature, now: day)
        await online.updateAll(now: day.addingTimeInterval(60), calendar: calendar)
        #expect(!attempts.contains(.nature))
        await online.updateAll(now: day.addingTimeInterval(86400), calendar: calendar)
        #expect(attempts.filter { $0 == .nature }.count == 1)
        await online.updateAll(now: day.addingTimeInterval(86430), calendar: calendar)
        #expect(attempts.filter { $0 == .nature }.count == 1)
        #expect(store.batch(.nature)?.images == images)
        #expect(online.status.contains("保留旧图"))
        let folders = try FileManager.default.contentsOfDirectory(at: store.folder(.nature), includingPropertiesForKeys: nil)
        #expect(folders.filter { UUID(uuidString: $0.lastPathComponent) != nil }.count == 1)
    }

    @Test func blockedSourceIsNotDownloaded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let curation = PhotoCuration(root: root.appendingPathComponent("Collection"))
        let url = try #require(PhotoLibrary.verificationPhotoURL)
        let photo = LibraryPhoto(sourceName: "fixture", image: try #require(PhotoLibrary.decode(url)), focalX: 0.5, focalY: 0.5,
                                 fileURL: url, identifier: "blocked-source")
        try curation.block(photo)
        let image = ReservoirImage(id: "blocked-source", title: "blocked", author: "test", source: URL(string: "https://example.com/source")!,
            download: URL(string: "https://example.com/image")!, license: "test fixture", licenseURL: URL(string: "https://example.com/license")!, provider: "fixture")
        var downloads = 0
        let online = OnlineReservoir(root: root.appendingPathComponent("Online"), curation: curation,
            candidates: { _, _, _ in [image] }, download: { _ in downloads += 1; return Data() })
        do { try await online.update(.nature); Issue.record("An incomplete replacement must not commit") } catch {}
        #expect(downloads == 0)
        #expect(online.store.batch(.nature) == nil)
    }
    @Test func manualCheckWorksWhileDailyUpdatesAreOffAndReportsProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ManualUpdate." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(false, forKey: "reservoirEnabled")
        for category in ImageCategory.allCases { defaults.set(Date(), forKey: "reservoirAttempt." + category.rawValue) }
        var requests = 0
        let online = OnlineReservoir(defaults: defaults, root: root,
            candidates: { _, _, _ in requests += 1; throw URLError(.notConnectedToInternet) })
        online.refresh()
        await Task.yield()
        #expect(requests == 0)
        var messages: [String] = []
        online.refresh(manual: true) { messages.append($0) }
        #expect(messages.first == "正在检查六类图库…")
        for _ in 0..<100 { if messages.last?.contains("检查未完成") == true { break }; await Task.yield() }
        #expect(requests == 6)
        #expect(messages.last?.contains("保留旧图") == true)
        #expect(!online.enabled)
    }

    @Test func alreadyCurrentLibraryHasAnExplicitResultWithoutDownloadingAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var downloads = 0
        let online = OnlineReservoir(root: root, candidates: { _, _, _ in downloads += 1; return [] })
        for category in ImageCategory.allCases {
            let stage = try online.store.begin(category)
            let entries = (0..<10).map { i in ReservoirImage(id: "fixture-\(i)", title: "test", author: "test",
                source: URL(string: "https://example.com")!, download: URL(string: "https://example.com")!,
                license: "fixture", licenseURL: URL(string: "https://example.com")!, provider: "fixture") }
            for entry in entries { try online.store.append(Data([1]), image: entry, stage: stage) }
            try online.store.commit(entries, stage: stage, category: category)
        }
        await online.updateAll(manual: true)
        #expect(downloads == 0)
        #expect(online.status.contains("今天的图库已是最新"))
    }

}
