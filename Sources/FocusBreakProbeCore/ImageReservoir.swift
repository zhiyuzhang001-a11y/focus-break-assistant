import Foundation

public struct ReservoirImage: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let author: String
    public let source: URL
    public let download: URL
    public let license: String
    public let licenseURL: URL
    public let provider: String
    public var filename: String { id + ".jpg" }
    public init(id: String, title: String, author: String, source: URL, download: URL, license: String, licenseURL: URL, provider: String) {
        self.id = id; self.title = title; self.author = author; self.source = source
        self.download = download; self.license = license; self.licenseURL = licenseURL; self.provider = provider
    }
}
public struct ReservoirBatch: Codable, Sendable {
    public let directory: String
    public let updatedAt: Date
    public let images: [ReservoirImage]
}

/// A manifest swap exposes either all ten old files or all ten new files.
/// User imports are stored elsewhere and never passed to this store.
public struct ImageReservoir: Sendable {
    public static let count = 10
    public static let categoryBytes = 20 * 1_024 * 1_024
    public static let imageBytes = 4 * 1_024 * 1_024
    public let root: URL
    public init(root: URL) { self.root = root }
    public func folder(_ category: ImageCategory) -> URL { root.appendingPathComponent(category.rawValue) }
    public func batch(_ category: ImageCategory) -> ReservoirBatch? {
        guard let data = try? Data(contentsOf: folder(category).appendingPathComponent("active.json")),
              let batch = try? JSONDecoder().decode(ReservoirBatch.self, from: data),
              UUID(uuidString: batch.directory) != nil, batch.images.count == Self.count,
              Set(batch.images.map(\.id)).count == Self.count,
              batch.images.allSatisfy({ Self.validID($0.id) && FileManager.default.fileExists(atPath: file($0, batch: batch, category: category).path) }) else { return nil }
        return batch
    }
    public func file(_ image: ReservoirImage, batch: ReservoirBatch, category: ImageCategory) -> URL {
        folder(category).appendingPathComponent(batch.directory).appendingPathComponent(image.filename)
    }
    public func begin(_ category: ImageCategory) throws -> URL {
        try repair(category)
        let stage = folder(category).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        return stage
    }
    public func append(_ data: Data, image: ReservoirImage, stage: URL) throws {
        guard Self.validID(image.id), !data.isEmpty, data.count <= Self.imageBytes,
              bytes(at: stage) + data.count < Self.categoryBytes - 65_536 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: stage.appendingPathComponent(image.filename), options: .atomic)
    }
    public func commit(_ images: [ReservoirImage], stage: URL, category: ImageCategory, now: Date = Date()) throws {
        guard stage.deletingLastPathComponent().standardizedFileURL == folder(category).standardizedFileURL,
              UUID(uuidString: stage.lastPathComponent) != nil,
              images.count == Self.count, Set(images.map(\.id)).count == Self.count,
              bytes(at: stage) < Self.categoryBytes - 65_536,
              images.allSatisfy({ Self.validID($0.id) && FileManager.default.fileExists(atPath: stage.appendingPathComponent($0.filename).path) }) else { throw CocoaError(.fileReadCorruptFile) }
        let batch = ReservoirBatch(directory: stage.lastPathComponent, updatedAt: now, images: images)
        let data = try JSONEncoder().encode(batch)
        guard data.count < 32_768 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: stage.appendingPathComponent("sources.json"), options: .atomic)
        try data.write(to: folder(category).appendingPathComponent("active.json"), options: .atomic)
        // Cleanup failure must not invalidate the already committed batch.
        try? repair(category)
    }
    public func repair(_ category: ImageCategory) throws {
        let folder = folder(category)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Keep the named batch even if a file is damaged, until a replacement succeeds.
        let named = (try? Data(contentsOf: folder.appendingPathComponent("active.json")))
            .flatMap { try? JSONDecoder().decode(ReservoirBatch.self, from: $0) }?.directory
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: url.lastPathComponent) != nil && url.lastPathComponent != named { try FileManager.default.removeItem(at: url) }
        }
    }
    public func bytes(at folder: URL? = nil) -> Int {
        guard let items = FileManager.default.enumerator(at: folder ?? root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        return items.compactMap { $0 as? URL }.reduce(0) { result, url in
            let info = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return result + (info?.isRegularFile == true ? info?.fileSize ?? 0 : 0)
        }
    }
    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count < 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
