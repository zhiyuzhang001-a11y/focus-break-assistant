import AppKit
import ImageIO
import FocusBreakProbeCore

@MainActor
struct LibraryPhoto {
    let sourceName: String
    let image: NSImage
    let focalX: Double
    let focalY: Double
    let fileURL: URL?
    let identifier: String
    let credit: PhotoCuration.Credit?
    let originalData: Data?
    init(sourceName: String, image: NSImage, focalX: Double, focalY: Double, fileURL: URL? = nil,
         identifier: String = "", credit: PhotoCuration.Credit? = nil) {
        self.sourceName = sourceName; self.image = image; self.focalX = focalX; self.focalY = focalY
        self.fileURL = fileURL; self.identifier = identifier.isEmpty ? sourceName : identifier; self.credit = credit
        self.originalData = fileURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
    }
}

@MainActor
final class PhotoLibrary {
    static let shared = PhotoLibrary()
    private let defaults: UserDefaults
    private let curation: PhotoCuration
    private var folder: URL?
    private var hasScopedAccess = false
    private var builtInRotation: PhotoRotation
    private struct BuiltInPhoto: Decodable {
        let resourceName: String
        let focalX: Double
        let focalY: Double
    }
    private static let builtInPhotos: [BuiltInPhoto] = {
        guard let url = Bundle.module.url(forResource: "BuiltInPhotos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let photos = try? JSONDecoder().decode([BuiltInPhoto].self, from: data),
              !photos.isEmpty else {
            return [BuiltInPhoto(resourceName: "Seascape", focalX: 0.5, focalY: 0.52)]
        }
        return photos
    }()
    private var rotation: PhotoRotation
    private(set) var status = "使用内置照片"
    var folderName: String? {
        guard let folder else { return nil }
        return folder.standardizedFileURL == PhotoImportStore.directory.standardizedFileURL
            ? "系统照片图库" : folder.lastPathComponent
    }

    init(defaults: UserDefaults = .standard, curation: PhotoCuration = .shared) {
        self.defaults = defaults
        self.curation = curation
        builtInRotation = defaults.data(forKey: "builtInPhotoRotation")
            .flatMap { try? JSONDecoder().decode(PhotoRotation.self, from: $0) } ?? PhotoRotation()
        rotation = defaults.data(forKey: "photoRotation")
            .flatMap { try? JSONDecoder().decode(PhotoRotation.self, from: $0) } ?? PhotoRotation()
        if let bookmark = defaults.data(forKey: "photoFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                folder = url
                hasScopedAccess = url.startAccessingSecurityScopedResource()
                if stale { try? persistFolder(url) }
            }
        }
    }

    func selectFolder(_ url: URL) throws {
        // Save successfully before replacing the user's previous selection.
        try persistFolder(url)
        defaults.set(false, forKey: "favoritesOnly")
        defaults.set(false, forKey: "categoryLibraryActive")
        defaults.set(false, forKey: "dailyPhotosSelected")
        if hasScopedAccess { folder?.stopAccessingSecurityScopedResource() }
        folder = url
        hasScopedAccess = url.startAccessingSecurityScopedResource()
        rotation = PhotoRotation()
        defaults.removeObject(forKey: "photoRotation")
        status = "照片文件夹：\(folderName ?? url.lastPathComponent)"
    }

    func useBuiltIn() {
        defaults.set(false, forKey: "favoritesOnly")
        defaults.set(false, forKey: "categoryLibraryActive")
        defaults.set(false, forKey: "dailyPhotosSelected")
        if hasScopedAccess { folder?.stopAccessingSecurityScopedResource() }
        folder = nil
        hasScopedAccess = false
        defaults.removeObject(forKey: "photoFolderBookmark")
        defaults.removeObject(forKey: "photoRotation")
        rotation = PhotoRotation()
        status = "使用内置照片"
    }

    private func persistFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "photoFolderBookmark")
    }

    func nextPhoto() -> LibraryPhoto? {
        let photo = selectNextPhoto()
        if let photo { curation.didShow(photo) }
        return photo
    }

    private func selectNextPhoto() -> LibraryPhoto? {
        if defaults.bool(forKey: "favoritesOnly"), let photo = curation.nextFavorite() {
            status = "收藏：" + (photo.credit?.title ?? photo.sourceName)
            return photo
        }
        if defaults.bool(forKey: "categoryLibraryActive") {
            if let photo = CategoryLibrary.shared.nextPhoto() {
                status = OnlineReservoir.shared.currentImage.map { "\($0.author) · \($0.license)" } ?? "今日图库：" + CategoryLibrary.shared.preferences.categories.map(\.title).joined(separator: "、")
                return photo
            }
        }
        if !defaults.bool(forKey: "categoryLibraryActive"), defaults.bool(forKey: "dailyPhotosSelected"), let photo = DailyPhotos.shared.nextPhoto() {
            status = DailyPhotos.shared.currentCredit ?? "每日照片 / Pexels"
            return photo
        }
        if !defaults.bool(forKey: "categoryLibraryActive"), !defaults.bool(forKey: "dailyPhotosSelected"), let folder {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            let paths = urls.filter {
                ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased())
                    && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.filter { curation.isAllowed($0, id: "local:" + $0.standardizedFileURL.path) }.map(\.path)
            // Rescan on every reminder, so additions/removals take effect without a restart.
            let avoid = Set(paths.filter { curation.shouldSeparate(URL(fileURLWithPath: $0)) })
            var tried = Set<String>()
            for _ in 0..<(paths.count * 2) {
                guard let path = rotation.next(in: paths, avoiding: avoid) else { break }
                guard tried.insert(path).inserted else { continue }
                if let image = Self.decode(URL(fileURLWithPath: path)) {
                    rotation.didShow(path)
                    defaults.set(try? JSONEncoder().encode(rotation), forKey: "photoRotation")
                    status = "照片文件夹：\(folderName ?? folder.lastPathComponent)"
                    return LibraryPhoto(sourceName: URL(fileURLWithPath: path).lastPathComponent, image: image, focalX: 0.5, focalY: 0.5, fileURL: URL(fileURLWithPath: path), identifier: "local:" + path, credit: .imported(URL(fileURLWithPath: path).lastPathComponent))
                }
            }
            status = "文件夹无可用照片，已使用内置照片"
        } else {
            status = defaults.bool(forKey: "categoryLibraryActive") ? "所选图库暂无可用图片，暂用内置风景" : "使用内置照片"
        }
        let names = Self.builtInPhotos.map(\.resourceName).filter { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "jpg") else { return false }
            return curation.isAllowed(url, id: "builtin:" + name)
        }
        let avoid = Set(names.filter { name in
            Bundle.module.url(forResource: name, withExtension: "jpg").map { curation.shouldSeparate($0) } ?? false
        })
        for _ in names {
            guard let name = builtInRotation.next(in: names, avoiding: avoid),
                  let metadata = Self.builtInPhotos.first(where: { $0.resourceName == name }),
                  let url = Bundle.module.url(forResource: name, withExtension: "jpg"),
                  let image = Self.decode(url) else { continue }
            builtInRotation.didShow(name)
            defaults.set(try? JSONEncoder().encode(builtInRotation), forKey: "builtInPhotoRotation")
            return LibraryPhoto(sourceName: "builtin:" + name, image: image,
                                focalX: metadata.focalX, focalY: metadata.focalY, fileURL: url, identifier: "builtin:" + name, credit: Self.builtInCredit(name))
        }
        status = curation.loadError ? "图片偏好记录无法读取，已保留数据；暂显示文字提醒" : "无可用且未屏蔽的图片，暂显示文字提醒"
        return nil
    }

    static var verificationPhotoURL: URL? { Bundle.module.url(forResource: "Seascape", withExtension: "jpg") }

    static func builtInCredit(_ name: String) -> PhotoCuration.Credit? {
        guard let url = Bundle.module.url(forResource: "BuiltInPhotos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let entry = entries.first(where: { $0["resourceName"] as? String == name }) else { return nil }
        return PhotoCuration.Credit(title: entry["title"] as? String ?? name,
            author: entry["photographer"] as? String ?? "见来源", source: entry["source"] as? String ?? "",
            license: "Pexels License", licenseURL: entry["license"] as? String ?? "")
    }

    static func verifyLibrary() throws -> [String: Bool] {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "FocusBreakPhotoTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: folder)
        }
        let sourceURL = Bundle.module.url(forResource: "Seascape", withExtension: "jpg")!
        try fm.copyItem(at: sourceURL, to: folder.appendingPathComponent("one.jpg"))
        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
        for (name, type) in [("two.png", "public.png"), ("three.heic", "public.heic")] {
            guard let destination = CGImageDestinationCreateWithURL(
                folder.appendingPathComponent(name) as CFURL, type as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        }
        try Data("broken image".utf8).write(to: folder.appendingPathComponent("broken.jpg"))
        let library = PhotoLibrary(defaults: defaults)
        try library.selectFolder(folder)
        let first = (0..<3).compactMap { _ in library.nextPhoto()?.sourceName }
        let restored = PhotoLibrary(defaults: defaults)
        let afterRestart = restored.nextPhoto()?.sourceName
        var results = [
            "jpegPngHeicDecoded": Set(first) == Set(["one.jpg", "two.png", "three.heic"]),
            "rotationSurvivesRestart": afterRestart != nil && afterRestart != first.last,
            "folderSurvivesRestart": restored.folderName == folder.lastPathComponent
        ]
        let importedFolder = folder.appendingPathComponent("Imported")
        let original = folder.appendingPathComponent("one.jpg")
        let originalBytes = try Data(contentsOf: original)
        let imported = try PhotoImportStore.importFile(original, into: importedFolder)
        let duplicate = try PhotoImportStore.importFile(original, into: importedFolder)
        let importedFiles = try fm.contentsOfDirectory(atPath: importedFolder.path)
        results["pickerImportDeduplicates"] = imported == duplicate && importedFiles.count == 1
        results["pickerImportPreservesOriginal"] = try Data(contentsOf: original) == originalBytes
        results["pickerImportReadable"] = Self.decode(imported) != nil
        do {
            _ = try PhotoImportStore.importFile(folder.appendingPathComponent("broken.jpg"), into: importedFolder)
            results["pickerImportRejectsCorruptFile"] = false
        } catch { results["pickerImportRejectsCorruptFile"] = true }
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: url)
        }
        results["emptyFolderFallsBack"] = restored.nextPhoto()?.sourceName.hasPrefix("builtin:") == true
        try fm.copyItem(at: sourceURL, to: folder.appendingPathComponent("added.jpg"))
        results["newFilePickedUp"] = restored.nextPhoto()?.sourceName == "added.jpg"
        try fm.removeItem(at: folder)
        results["missingFolderFallsBack"] = restored.nextPhoto()?.sourceName.hasPrefix("builtin:") == true
        library.useBuiltIn()
        restored.useBuiltIn()
        let count = Self.builtInPhotos.count
        let firstRound = (0..<count).compactMap { _ in library.nextPhoto()?.sourceName }
        let nextRound = library.nextPhoto()?.sourceName
        results["builtInPhotosDecodeAndRotate"] = firstRound.count == count && Set(firstRound).count == count
        results["builtInRoundBoundaryDoesNotRepeat"] = count == 1 || firstRound.last != nextRound
        return results
    }

    // ImageIO applies EXIF orientation and downsamples before decoding large phone photos.
    static func decode(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3200,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
