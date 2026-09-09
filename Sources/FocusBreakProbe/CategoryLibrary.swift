import AppKit
import FocusBreakProbeCore

@MainActor
final class CategoryLibrary {
    static let shared = CategoryLibrary()
    let preferences: ImagePreferences
    let root: URL
    private let defaults: UserDefaults
    private let online: OnlineReservoir
    private let curation: PhotoCuration
    private var rotation: PhotoRotation
    init(defaults: UserDefaults = .standard, root: URL? = nil) {
        self.defaults = defaults
        self.curation = root.map { PhotoCuration(root: $0.appendingPathComponent("TestCollection")) } ?? .shared
        self.online = root.map { OnlineReservoir(defaults: defaults, root: $0.appendingPathComponent("TestOnlineReservoir")) } ?? .shared
        preferences = ImagePreferences(defaults: defaults)
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant/CategoryImages")
        rotation = defaults.data(forKey: "categoryImageRotation")
            .flatMap { try? JSONDecoder().decode(PhotoRotation.self, from: $0) } ?? PhotoRotation()
    }
    func directory(_ category: ImageCategory) -> URL { root.appendingPathComponent(category.rawValue) }
    func localFiles(_ category: ImageCategory) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory(category), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    func files(_ category: ImageCategory) -> [URL] {
        var files = localFiles(category)
        let online = self.online.files(category)
        files += online
        if category == .nature && online.isEmpty && files.isEmpty {
            files += ["AlpineLake", "ValleyReflection", "GreenHills", "RollingMeadow", "RockyCoast", "Seascape"]
                .compactMap { Bundle.module.url(forResource: $0, withExtension: "jpg") }
        }
        return files
    }
    func importFiles(_ urls: [URL], category: ImageCategory) -> (success: Int, failed: Int) {
        var success = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let destination = try PhotoImportStore.importFile(url, into: directory(category))
                let record = ["filename": destination.lastPathComponent, "originalFilename": url.lastPathComponent,
                              "source": "user-provided", "license": "user-managed; not independently verified",
                              "importedAt": ISO8601DateFormatter().string(from: Date())]
                try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
                    .write(to: destination.appendingPathExtension("source.json"), options: .atomic)
                success += 1
            } catch { continue }
        }
        return (success, urls.count - success)
    }
    func nextPhoto() -> LibraryPhoto? {
        DailyPhotos.shared.recordSource(for: root)
        online.recordSource(root)
        let urls = Array(Set(preferences.categories.flatMap(files)))
        let metadata = Dictionary(uniqueKeysWithValues: urls.compactMap { url in online.metadata(url).map { (url.path, $0) } })
        let paths = urls.filter { curation.isAllowed($0, id: metadata[$0.path]?.id ?? "local:" + $0.path) }.map(\.path)
        let avoid = Set(paths.filter { curation.shouldSeparate(URL(fileURLWithPath: $0), title: metadata[$0]?.title ?? "") })
        for _ in 0..<(paths.count * 2) {
            guard let path = rotation.next(in: paths, avoiding: avoid), let image = PhotoLibrary.decode(URL(fileURLWithPath: path)) else { continue }
            rotation.didShow(path)
            defaults.set(try? JSONEncoder().encode(rotation), forKey: "categoryImageRotation")
            DailyPhotos.shared.recordSource(for: URL(fileURLWithPath: path))
            online.recordSource(URL(fileURLWithPath: path))
            return LibraryPhoto(sourceName: "category:" + URL(fileURLWithPath: path).lastPathComponent, image: image, focalX: 0.5, focalY: 0.5, fileURL: URL(fileURLWithPath: path), identifier: metadata[path]?.id ?? "local:" + path,
                credit: metadata[path]?.credit ?? PhotoLibrary.builtInCredit(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) ?? .imported(URL(fileURLWithPath: path).lastPathComponent))
        }
        return nil
    }
}
