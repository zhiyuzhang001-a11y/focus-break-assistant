import AppKit
import Security
import LocalAuthentication
import ImageIO
import FocusBreakProbeCore

@MainActor
final class DailyPhotos {
    static let shared = DailyPhotos()
    let cache: DailyPhotoCache
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        cache = DailyPhotoCache(directory: directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant/DailyPhotos", isDirectory: true))
        rotation = defaults.data(forKey: "dailyPhotoRotation")
            .flatMap { try? JSONDecoder().decode(PhotoRotation.self, from: $0) } ?? PhotoRotation()
    }
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var rotation = PhotoRotation()
    private(set) var status = "每日照片：尚未配置"
    private(set) var currentSource: URL?
    private(set) var currentCredit: String?
    var enabled: Bool { defaults.bool(forKey: "dailyPhotosEnabled") }
    var selected: Bool {
        get { defaults.bool(forKey: "dailyPhotosSelected") }
        set { defaults.set(newValue, forKey: "dailyPhotosSelected") }
    }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "FocusBreakAssistant.Pexels",
         kSecAttrAccount as String: "api-key"]
    }
    func saveKey(_ value: String) throws {
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
        let query = keyQuery
        var result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        defaults.set(true, forKey: "dailyPhotosEnabled")
        selected = true
        refresh(force: true)
    }
    private func key() -> String? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background refresh must not unexpectedly display a Keychain password prompt.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func start() {
        do { try cache.repair() } catch { status = "每日照片：缓存不可写" }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 60
    }
    func stopUpdates() {
        generation += 1; task?.cancel(); task = nil
        defaults.set(false, forKey: "dailyPhotosEnabled")
        status = "每日更新已关闭；缓存仍可使用"
    }
    func clear() throws {
        generation += 1; task?.cancel(); task = nil
        try cache.clear()
        currentSource = nil; currentCredit = nil
        // Do not immediately refill after an explicit clear.
        stopUpdates()
        status = "缓存已清空，每日更新已关闭"
    }
    func preferencesChanged() {
        generation += 1; task?.cancel(); task = nil
        refresh(force: true)
    }
    func recordSource(for file: URL) {
        let photo = cache.photos().first { cache.directory.appendingPathComponent($0.filename) == file }
        currentSource = photo?.sourceURL
        currentCredit = photo.map { "照片：\($0.photographer) / Pexels" }
    }
    func refresh(force: Bool = false) {
        guard task == nil, enabled else { return }
        if ImagePreferences(defaults: defaults).categories.allSatisfy({ $0.onlineQuery == nil }) {
            status = "所选分类仅使用本地图库"; return
        }
        let today = Self.dayKey(Date())
        if !force {
            if defaults.string(forKey: "dailyPhotosSuccessDay") == today { status = "今日照片已更新（\(cache.photos().count) 张缓存）"; return }
            if let last = defaults.object(forKey: "dailyPhotosAttempt") as? Date, Date().timeIntervalSince(last) < 3600 { return }
        }
        guard let key = key() else { status = "每日照片：请配置 Pexels API 密钥"; return }
        defaults.set(Date(), forKey: "dailyPhotosAttempt")
        let token = generation
        status = "正在获取今日照片…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.task = nil } }
            do {
                let count = try await self.fetch(key: key, day: today, token: token)
                guard token == self.generation else { return }
                if count == 3 { self.defaults.set(today, forKey: "dailyPhotosSuccessDay") }
                self.status = count == 3 ? "今日已获取 3 张照片" : "今日已获取 \(count)/3 张，稍后补充"
            } catch {
                guard token == self.generation else { return }
                self.status = (error as? FetchError) == .authorization
                    ? "Pexels 密钥无效或失效，请重新配置" : "更新暂不可用，继续使用缓存或内置照片"
            }
        }
    }
    private enum FetchError: Error { case authorization, invalidResponse, tooLarge }
    private struct Response: Decodable { let photos: [Photo] }
    private struct Photo: Decodable {
        let id: Int; let photographer: String; let url: URL; let src: [String: URL]
    }
    func fetch(key: String, day: String, token: Int, testSession: URLSession? = nil) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 90
        let session = testSession ?? URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var count = defaults.string(forKey: "dailyPhotosProgressDay") == day ? defaults.integer(forKey: "dailyPhotosProgressCount") : 0
        if count >= 3 { return 3 }
        let preferences = ImagePreferences(defaults: defaults)
        let categories = preferences.categories.filter { $0.onlineQuery != nil }
        guard !categories.isEmpty else { return count }
        let index = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1
        let initialCount = count
        for offset in 0..<3 where count < 3 {
        let category = categories[(index + initialCount + offset) % categories.count]
        var query = category.onlineQuery!
        if category == .people {
            query = ["生活纪实": "people daily life", "运动": "people sports", "时尚": "fashion people"][preferences.peopleStyle] ?? query
        }
        let target = count + 1
        var components = URLComponents(string: "https://api.pexels.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "orientation", value: "landscape"), URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: String(1 + (index / 7) % 10))]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "Authorization")
        let body = try await limitedData(request, session: session, limit: 1_024 * 1_024)
        let photos = try JSONDecoder().decode(Response.self, from: body).photos.shuffled()
        var existing = Set(cache.photos().map(\.id))
        var attempts = 0
        for photo in photos where count < target && !existing.contains(photo.id) {
            guard attempts < 6 else { break }
            try Task.checkCancellation()
            guard token == generation, photo.id > 0, photo.url.scheme == "https",
                  photo.url.absoluteString.count < 4096,
                  ["www.pexels.com", "pexels.com"].contains(photo.url.host ?? ""),
                  let original = photo.src["original"], original.scheme == "https", original.host == "images.pexels.com",
                  var imageURL = URLComponents(url: original, resolvingAgainstBaseURL: false) else { continue }
            imageURL.queryItems = [URLQueryItem(name: "auto", value: "compress"), URLQueryItem(name: "w", value: "2560")]
            guard let url = imageURL.url else { continue }
            attempts += 1
            do {
                let data = try await limitedData(URLRequest(url: url), session: session, limit: DailyPhotoCache.maximumPhotoBytes)
                guard token == generation else { throw CancellationError() }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) != nil else { continue }
                try cache.insert(data, photo: CachedPhoto(id: photo.id, photographer: String(photo.photographer.prefix(200)), sourceURL: photo.url, category: category.rawValue))
                existing.insert(photo.id); count += 1
                defaults.set(day, forKey: "dailyPhotosProgressDay")
                defaults.set(count, forKey: "dailyPhotosProgressCount")
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        }
        return count
    }
    nonisolated private func limitedData(_ request: URLRequest, session: URLSession, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.invalidResponse }
        if [401, 403].contains(http.statusCode) { throw FetchError.authorization }
        guard http.statusCode == 200 else { throw FetchError.invalidResponse }
        guard response.expectedContentLength <= Int64(limit) else { throw FetchError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw FetchError.tooLarge }
            data.append(byte)
        }
        return data
    }
    func nextPhoto() -> LibraryPhoto? {
        currentSource = nil; currentCredit = nil
        let photos = cache.photos().filter { PhotoCuration.shared.isAllowed(cache.directory.appendingPathComponent($0.filename), id: "pexels:\($0.id)") }
        for _ in 0..<(photos.count * 2) {
            guard let id = rotation.next(in: photos.map { String($0.id) }), let photo = photos.first(where: { String($0.id) == id }),
                  let image = PhotoLibrary.decode(cache.directory.appendingPathComponent(photo.filename)) else { continue }
            rotation.didShow(id)
            defaults.set(try? JSONEncoder().encode(rotation), forKey: "dailyPhotoRotation")
            currentSource = photo.sourceURL; currentCredit = "照片：\(photo.photographer) / Pexels"
            return LibraryPhoto(sourceName: "pexels:\(photo.id)", image: image, focalX: 0.5, focalY: 0.5, fileURL: cache.directory.appendingPathComponent(photo.filename), identifier: "pexels:\(photo.id)", credit: PhotoCuration.Credit(title: photo.filename, author: photo.photographer, source: photo.sourceURL.absoluteString, license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))
        }
        return nil
    }
    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}
