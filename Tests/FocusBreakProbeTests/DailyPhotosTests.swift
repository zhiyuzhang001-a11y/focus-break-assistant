import Foundation
import Testing
@testable import FocusBreakProbe

private final class PhotoProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseStatus = 200
    nonisolated(unsafe) static var corrupt = false
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let url = request.url!
        let data: Data
        if url.host == "api.pexels.com" {
            let photos = (1...6).map { ["id": $0, "photographer": "Photographer \($0)", "url": "https://www.pexels.com/photo/\($0)/", "src": ["original": "https://images.pexels.com/photos/\($0)/photo.jpeg"]] as [String: Any] }
            data = try! JSONSerialization.data(withJSONObject: ["photos": photos])
        } else if Self.corrupt { data = Data("not a photo".utf8) }
        else {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            data = try! Data(contentsOf: root.appendingPathComponent("Sources/FocusBreakProbe/Resources/Seascape.jpg"))
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: Self.responseStatus, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct DailyPhotosTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func dailyQuotaCorruptionAuthorizationAndClear() async throws {
        let suite = "DailyPhotosTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let daily = DailyPhotos(defaults: defaults, directory: folder)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        PhotoProtocol.responseStatus = 200; PhotoProtocol.corrupt = false; PhotoProtocol.requests = 0
        let first = try await daily.fetch(key: "test", day: "2026-9-6", token: 0, testSession: session())
        #expect(first == 3)
        #expect(daily.cache.photos().count == 3)
        #expect(daily.cache.photos().allSatisfy { $0.category == "nature" })
        #expect(daily.nextPhoto() != nil)
        #expect(daily.currentSource?.host == "www.pexels.com")
        let requests = PhotoProtocol.requests
        let repeated = try await daily.fetch(key: "test", day: "2026-9-6", token: 0, testSession: session())
        #expect(repeated == 3)
        #expect(PhotoProtocol.requests == requests)
        defaults.set(["cartoon", "space"], forKey: "imageCategories")
        let localOnly = try await daily.fetch(key: "test", day: "2026-9-7", token: 0, testSession: session())
        #expect(localOnly == 0)
        #expect(PhotoProtocol.requests == requests)
        defaults.set(["animals", "city"], forKey: "imageCategories")
        PhotoProtocol.corrupt = true
        let failed = try await daily.fetch(key: "test", day: "2026-9-7", token: 0, testSession: session())
        #expect(failed == 0)
        #expect(daily.cache.photos().count == 3)
        PhotoProtocol.responseStatus = 401
        await #expect(throws: (any Error).self) {
            _ = try await daily.fetch(key: "invalid", day: "2026-9-7", token: 0, testSession: session())
        }
        #expect(daily.cache.photos().count == 3)
        try daily.clear()
        #expect(daily.cache.photos().isEmpty)
        #expect(!daily.enabled)
        #expect(daily.nextPhoto() == nil)
        PhotoProtocol.responseStatus = 200; PhotoProtocol.corrupt = false
        _ = try await daily.fetch(key: "test", day: "2026-9-8", token: 0, testSession: session())
        #expect(daily.cache.photos().isEmpty) // A stale pre-clear task cannot repopulate the cache.
    }
}
