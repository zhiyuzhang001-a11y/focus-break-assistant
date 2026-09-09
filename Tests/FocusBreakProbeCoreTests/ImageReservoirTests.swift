import Foundation
import Testing
@testable import FocusBreakProbeCore

struct ImageReservoirTests {
    func image(_ id: Int) -> ReservoirImage {
        ReservoirImage(id: "image-\(id)", title: "Test", author: "Author", source: URL(string: "https://example.org/\(id)")!, download: URL(string: "https://example.org/image.jpg")!, license: "CC0", licenseURL: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!, provider: "Fixture")
    }
    @Test func incompleteBatchNeverReplacesOldAndCommitRemovesOld() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ImageReservoir(root: root)
        let first = try store.begin(.nature)
        let old = (0..<10).map(image)
        for item in old { try store.append(Data([1]), image: item, stage: first) }
        try store.commit(old, stage: first, category: .nature)
        let next = try store.begin(.nature)
        let new = (10..<20).map(image)
        for item in new.prefix(9) { try store.append(Data([2]), image: item, stage: next) }
        #expect(throws: (any Error).self) { try store.commit(Array(new.prefix(9)), stage: next, category: .nature) }
        #expect(store.batch(.nature)?.images == old)
        try store.append(Data([2]), image: new[9], stage: next)
        try store.commit(new, stage: next, category: .nature)
        #expect(store.batch(.nature)?.images == new)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(store.batch(.city) == nil)
        let interrupted = try store.begin(.nature)
        try store.append(Data([1]), image: image(99), stage: interrupted)
        try ImageReservoir(root: root).repair(.nature)
        #expect(!FileManager.default.fileExists(atPath: interrupted.path))
        #expect(store.batch(.nature)?.images.count == 10)
    }
    @Test func respectsByteLimitAndRejectsUnsafeNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ImageReservoir(root: root)
        let stage = try store.begin(.cartoon)
        for id in 0..<4 { try store.append(Data(repeating: 1, count: ImageReservoir.imageBytes), image: image(id), stage: stage) }
        #expect(throws: (any Error).self) { try store.append(Data(repeating: 1, count: ImageReservoir.imageBytes), image: image(4), stage: stage) }
        #expect(store.bytes(at: stage) < ImageReservoir.categoryBytes)
        let unsafe = ReservoirImage(id: "../foreign", title: "", author: "", source: image(1).source, download: image(1).download, license: "", licenseURL: image(1).licenseURL, provider: "")
        #expect(throws: (any Error).self) { try store.append(Data([1]), image: unsafe, stage: stage) }
    }
}

struct ReservoirContentPolicyTests {
    @Test func excludesArtAndNonHumanPortraits() {
        #expect(!ReservoirContentPolicy.accepts(.nature, metadata: "Landscape paintings; oil on canvas"))
        #expect(!ReservoirContentPolicy.accepts(.people, metadata: "Portrait of a male gull; Birds"))
        #expect(!ReservoirContentPolicy.accepts(.people, metadata: "Portrait of a Carpathian Lynx"))
        #expect(!ReservoirContentPolicy.accepts(.people, metadata: "Portrait of a man on a herm; marble bust"))
        #expect(!ReservoirContentPolicy.accepts(.people, metadata: "Portrait of young man by Sandro Botticelli - Louvre"))
        #expect(!ReservoirContentPolicy.accepts(.people, metadata: "Woman in lingerie; portrait"))
        #expect(ReservoirContentPolicy.accepts(.people, metadata: "Portrait photographs of women, person in city"))
        #expect(ReservoirContentPolicy.accepts(.nature, metadata: "Mountain lake; landscape photographs"))
        #expect(!ReservoirContentPolicy.accepts(.animals, metadata: "Elephant's trunk nebula"))
    }
}
