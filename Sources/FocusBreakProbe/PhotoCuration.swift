import AppKit
import CryptoKit
import ImageIO
import FocusBreakProbeCore

/// Local feedback and retained originals. No generated assets or face identity inference.
@MainActor
final class PhotoCuration {
    static let shared = PhotoCuration()
    struct Credit: Codable, Equatable {
        var title: String
        var author: String
        var source: String
        var license: String
        var licenseURL: String
        static func imported(_ name: String) -> Credit {
            Credit(title: name, author: "用户提供", source: "user-provided", license: "用户管理；未经独立核实", licenseURL: "")
        }
    }
    struct Favorite: Codable {
        let id: String
        let filename: String
        let digest: String
        let credit: Credit
        let savedAt: Date
    }
    struct Block: Codable {
        let id: String
        let digest: String
        let title: String
    }
    private struct State: Codable {
        var favorites: [Favorite] = []
        var blocked: [Block] = []
    }
    struct Signature {
        let digest: String
        let hash: UInt64
    }
    private struct CachedSignature {
        let date: Date?
        let size: Int?
        let signature: Signature
    }
    let root: URL
    private var state: State
    private var cache: [URL: CachedSignature] = [:]
    private var lastHash: UInt64?
    private var lastSubject: String?
    private var rotation = PhotoRotation()
    private(set) var loadError = false

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant/PersonalCollection")
        let manifest = self.root.appendingPathComponent("collection.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            do {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: manifest))
                guard state.favorites.allSatisfy({ entry in
                    entry.digest.count == 64 && entry.digest.allSatisfy({ $0.isHexDigit && $0.isASCII }) &&
                    ["jpg", "jpeg", "png", "heic"].contains(URL(fileURLWithPath: entry.filename).pathExtension.lowercased()) &&
                    entry.filename == entry.digest + "." + URL(fileURLWithPath: entry.filename).pathExtension.lowercased()
                }) else { throw CocoaError(.fileReadCorruptFile) }
            }
            catch { state = State(); loadError = true }
        } else { state = State() }
    }
    var favorites: [Favorite] { state.favorites }
    var blocked: [Block] { state.blocked }
    func file(_ favorite: Favorite) -> URL { root.appendingPathComponent("Favorites").appendingPathComponent(favorite.filename) }
    private func save(_ next: State) throws {
        guard !loadError else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: root.appendingPathComponent("collection.json"), options: .atomic)
        state = next
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func signature(_ data: Data) -> Signature? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
              ] as CFDictionary) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8,
                bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8)); return true
        }
        guard rendered else { return nil }
        var hash: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { if pixels[y * 9 + x] > pixels[y * 9 + x + 1] { hash |= 1 << (y * 8 + x) } } }
        return Signature(digest: digest(data), hash: hash)
    }
    func signature(_ url: URL) -> Signature? {
        let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        if let entry = cache[url], entry.date == info?.contentModificationDate, entry.size == info?.fileSize { return entry.signature }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let signature = Self.signature(data) else { return nil }
        if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
        cache[url] = CachedSignature(date: info?.contentModificationDate, size: info?.fileSize, signature: signature)
        return signature
    }
    static func similar(_ a: UInt64, _ b: UInt64) -> Bool { (a ^ b).nonzeroBitCount <= 8 }
    static func subject(_ title: String) -> String {
        var name = title.lowercased().replacingOccurrences(of: "file:", with: "")
            .replacingOccurrences(of: #"\.(jpg|jpeg|png|heic)$"#, with: "", options: .regularExpression)
        // Portrait sequence numbers can denote a burst of the same subject. Keep
        // astronomical catalog numbers and other meaningful numeric identities.
        if name.contains("portrait") || name.contains("headshot") {
            name = name.replacingOccurrences(of: #"[ _-]+\(?[0-9]{1,6}\)?$"#, with: "", options: .regularExpression)
        }
        return name.replacingOccurrences(of: #"[\W_]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    func isBlocked(id: String, digest: String? = nil) -> Bool {
        loadError || state.blocked.contains { $0.id == id || (digest != nil && $0.digest == digest) }
    }
    func isAllowed(_ url: URL, id: String) -> Bool {
        guard !isBlocked(id: id), let signature = signature(url) else { return false }
        return !isBlocked(id: id, digest: signature.digest)
    }
    func shouldSeparate(_ url: URL, title: String = "") -> Bool {
        if let lastSubject, !title.isEmpty, Self.subject(title) == lastSubject { return true }
        guard let lastHash, let signature = signature(url) else { return false }
        return Self.similar(lastHash, signature.hash)
    }
    func didShow(_ photo: LibraryPhoto) {
        lastHash = photo.fileURL.flatMap { signature($0)?.hash }
        lastSubject = photo.credit.map { Self.subject($0.title) }
    }
    func isFavorite(_ photo: LibraryPhoto) -> Bool {
        let digest = photo.originalData.map(Self.digest)
        return state.favorites.contains { $0.id == photo.identifier || $0.digest == digest }
    }
    func favorite(_ photo: LibraryPhoto) throws {
        guard !loadError else { throw CocoaError(.fileReadCorruptFile) }
        guard let url = photo.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try photo.originalData ?? Data(contentsOf: url)
        let digest = Self.digest(data)
        guard !state.favorites.contains(where: { $0.id == photo.identifier || $0.digest == digest }) else { return }
        let filename = digest + "." + url.pathExtension.lowercased()
        let folder = root.appendingPathComponent("Favorites")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let credit = photo.credit ?? .imported(photo.sourceName)
        let entry = Favorite(id: photo.identifier, filename: filename, digest: digest, credit: credit, savedAt: Date())
        // Original bytes plus an adjacent license record; manifest is published last.
        try data.write(to: folder.appendingPathComponent(filename), options: .atomic)
        try JSONEncoder().encode(entry).write(to: folder.appendingPathComponent(filename + ".source.json"), options: .atomic)
        var next = state; next.favorites.append(entry)
        try save(next)
    }
    func block(_ photo: LibraryPhoto) throws {
        guard let data = photo.originalData, let signature = Self.signature(data) else { throw CocoaError(.fileReadUnknown) }
        var next = state
        if !next.blocked.contains(where: { $0.id == photo.identifier }) {
            next.blocked.append(Block(id: photo.identifier, digest: signature.digest, title: photo.credit?.title ?? photo.sourceName))
        }
        try save(next)
    }
    func restore(id: String) throws { var next = state; next.blocked.removeAll { $0.id == id }; try save(next) }
    func restoreBlocked() throws { var next = state; next.blocked = []; try save(next) }
    func removeFavorite(id: String) throws {
        guard let entry = state.favorites.first(where: { $0.id == id }) else { return }
        var next = state; next.favorites.removeAll { $0.id == id }; try save(next)
        // Only our retained copies are removed, never the source original.
        try? FileManager.default.removeItem(at: file(entry))
        try? FileManager.default.removeItem(at: file(entry).appendingPathExtension("source.json"))
    }
    func nextFavorite() -> LibraryPhoto? {
        let entries = state.favorites.filter { isAllowed(file($0), id: $0.id) }
        let avoid = Set(entries.filter { shouldSeparate(file($0), title: $0.credit.title) }.map(\.id))
        for _ in entries {
            guard let id = rotation.next(in: entries.map(\.id), avoiding: avoid), let entry = entries.first(where: { $0.id == id }),
                  let image = PhotoLibrary.decode(file(entry)) else { continue }
            rotation.didShow(id)
            return LibraryPhoto(sourceName: entry.credit.title, image: image, focalX: 0.5, focalY: 0.5,
                fileURL: file(entry), identifier: entry.id, credit: entry.credit)
        }
        return nil
    }
}
