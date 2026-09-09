import Foundation

public struct CachedPhoto: Codable, Sendable, Equatable {
    public let category: String?
    public let id: Int
    public let photographer: String
    public let sourceURL: URL
    public let downloadedAt: Date
    public var filename: String { "pexels-\(id).jpg" }
    public init(id: Int, photographer: String, sourceURL: URL, downloadedAt: Date = Date(), category: String? = nil) {
        self.category = category
        self.id = id; self.photographer = photographer; self.sourceURL = sourceURL; self.downloadedAt = downloadedAt
    }
}

/// Owns only its dedicated cache directory. Personal photo folders never enter this API.
public struct DailyPhotoCache {
    public static let maximumBytes = 30 * 1_024 * 1_024
    public static let maximumCount = 10
    public static let maximumPhotoBytes = 6 * 1_024 * 1_024
    public let directory: URL
    private let fm = FileManager.default
    private var manifestURL: URL { directory.appendingPathComponent("sources.json") }
    public init(directory: URL) { self.directory = directory }
    public func photos() -> [CachedPhoto] {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([CachedPhoto].self, from: data) else { return [] }
        return entries.filter { $0.id > 0 && fm.fileExists(atPath: directory.appendingPathComponent($0.filename).path) }
    }
    public var bytesUsed: Int {
        files().reduce(0) { $0 + size($1) }
    }
    public func clear() throws {
        for url in files() { try fm.removeItem(at: url) }
    }
    public func repair() throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries = photos().sorted { $0.downloadedAt < $1.downloadedAt }
        let known = Set(entries.map(\.filename) + ["sources.json"])
        for url in files() where !known.contains(url.lastPathComponent) { try fm.removeItem(at: url) }
        while entries.count > Self.maximumCount || bytesUsed > Self.maximumBytes - 65_536 {
            guard !entries.isEmpty else { break }
            try fm.removeItem(at: directory.appendingPathComponent(entries.removeFirst().filename))
        }
        try save(entries)
    }
    public func insert(_ data: Data, photo: CachedPhoto) throws {
        guard photo.id > 0, !data.isEmpty, data.count <= Self.maximumPhotoBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try repair()
        var entries = photos().filter { $0.id != photo.id }.sorted { $0.downloadedAt < $1.downloadedAt }
        let destination = directory.appendingPathComponent(photo.filename)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        // Reserve the incoming image and metadata space before the atomic write.
        while entries.count >= Self.maximumCount || bytesUsed + data.count > Self.maximumBytes - 65_536 {
            guard !entries.isEmpty else { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.removeItem(at: directory.appendingPathComponent(entries.removeFirst().filename))
        }
        try data.write(to: destination, options: .atomic)
        entries.append(photo)
        try save(entries)
    }
    private func save(_ entries: [CachedPhoto]) throws {
        try JSONEncoder().encode(entries).write(to: manifestURL, options: .atomic)
    }
    private func files() -> [URL] {
        (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    }
    private func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}
