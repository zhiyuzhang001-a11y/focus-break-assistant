import Foundation
import ImageIO
import FocusBreakProbeCore

struct ReservoirProvider: Sendable {
    static let userAgent = "FocusBreakAssistant/0.4 (personal macOS image viewer; https://www.mediawiki.org/wiki/API:Etiquette)"
    enum Failure: Error { case response(Int), invalid, oversized }
    func candidates(_ category: ImageCategory, page: Int, peopleStyle: String) async throws -> [ReservoirImage] {
        switch category {
        case .space: return try await nasa(page: page)
        case .cartoon: return try await openclipart(page: page)
        default: return try await commons(category, page: page, peopleStyle: peopleStyle)
        }
    }
    func download(_ image: ReservoirImage) async throws -> Data {
        let data = try await fetch(image.download, limit: ImageReservoir.imageBytes)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              min(width, height) >= 400,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) != nil else { throw Failure.invalid }
        return data
    }
    func fetch(_ url: URL, limit: Int = 2 * 1_024 * 1_024) async throws -> Data {
        let hosts = ["commons.wikimedia.org", "upload.wikimedia.org", "thumb.wikimedia.org", "images-api.nasa.gov", "images-assets.nasa.gov", "openclipart.org"]
        guard url.scheme == "https", hosts.contains(url.host ?? "") else { throw Failure.invalid }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard response.expectedContentLength <= limit else { throw Failure.oversized }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < limit else { throw Failure.oversized }
            data.append(byte)
        }
        return data
    }
    private func url(_ base: String, _ params: [String: String]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    private func json(_ url: URL) async throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: await fetch(url)) as? [String: Any] else { throw Failure.invalid }
        return result
    }
    private func clean(_ string: String) -> String {
        String(string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").prefix(350))
    }
    private func commons(_ category: ImageCategory, page: Int, peopleStyle: String) async throws -> [ReservoirImage] {
        var query = [ImageCategory.nature: "mountain lake", .animals: "(elephant OR fox OR tiger OR deer OR bird)", .city: "city skyline", .people: "portrait (woman OR man OR people)"][category]!
        if category == .people {
            query = page % 2 == 0 ? "intitle:portrait woman" : "intitle:portrait man"
            if peopleStyle == "运动" { query = "athlete sports portrait" }
            if peopleStyle == "时尚" { query = "fashion portrait photography" }
        }
        let response = try await json(url("https://commons.wikimedia.org/w/api.php", [
            "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6", "gsrlimit": "20",
            "gsroffset": String((category == .people ? page / 2 : page) * 20), "gsrsearch": "incategory:\"Quality images\" " + query,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": "1280",
            "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl|ImageDescription|Categories", "maxlag": "5"
        ]))
        guard let queryResult = response["query"] as? [String: Any], let pages = queryResult["pages"] as? [String: [String: Any]] else { return [] }
        return pages.values.compactMap { page in
            guard let id = page["pageid"] as? Int, let title = page["title"] as? String,
                  let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  let metadata = info["extmetadata"] as? [String: [String: Any]],
                  let license = metadata["LicenseShortName"]?["value"] as? String,
                  ["CC BY", "CC0", "Public domain"].contains(where: { license.hasPrefix($0) }),
                  let download = (info["thumburl"] ?? info["url"]) as? String, let downloadURL = URL(string: download),
                  let source = info["descriptionurl"] as? String, let sourceURL = URL(string: source) else { return nil }
            let description = ((metadata["ImageDescription"]?["value"] as? String ?? "") + " " + (metadata["Categories"]?["value"] as? String ?? "") + " " + title).lowercased()
            guard ReservoirContentPolicy.accepts(category, metadata: description) else { return nil }
            if category == .people && !title.lowercased().contains("portrait") { return nil }
            let licenseLink = metadata["LicenseUrl"]?["value"] as? String ?? "https://commons.wikimedia.org/wiki/Commons:Licensing"
            guard let licenseURL = URL(string: licenseLink.hasPrefix("//") ? "https:" + licenseLink : licenseLink) else { return nil }
            return ReservoirImage(id: "commons-\(id)", title: clean(title), author: clean(metadata["Artist"]?["value"] as? String ?? "见来源页"), source: sourceURL, download: downloadURL, license: license, licenseURL: licenseURL, provider: "Wikimedia Commons")
        }
    }
    private func nasa(page: Int) async throws -> [ReservoirImage] {
        let response = try await json(url("https://images-api.nasa.gov/search", ["q": "nebula", "media_type": "image", "page_size": "30", "page": String(page + 1)]))
        let collection = response["collection"] as? [String: Any]
        return (collection?["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let data = (item["data"] as? [[String: Any]])?.first,
                  let id = data["nasa_id"] as? String, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  let title = data["title"] as? String else { return nil }
            let description = (data["description"] as? String ?? "").lowercased()
            guard !["artist", "illustration", "animation", "concept", "diagram", "copyright", "©"].contains(where: description.contains) else { return nil }
            let author = data["secondary_creator"] as? String ?? "NASA"
            guard author.contains("NASA") else { return nil }
            let links = item["links"] as? [[String: Any]] ?? []
            let image = links.first { ($0["width"] as? Int ?? 0) >= 1000 && ($0["width"] as? Int ?? 99999) <= 2000 }
                ?? links.first { ($0["rel"] as? String) == "preview" }
            guard let link = image?["href"] as? String, let download = URL(string: link) else { return nil }
            return ReservoirImage(id: "nasa-" + id, title: clean(title), author: clean(author), source: url("https://images.nasa.gov/details/" + id, [:]), download: download,
                license: "NASA media usage guidelines; credit retained", licenseURL: URL(string: "https://www.nasa.gov/nasa-brand-center/images-and-media/")!, provider: "NASA Image Library")
        }
    }
    private func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
    private func openclipart(page: Int) async throws -> [ReservoirImage] {
        let search = url("https://openclipart.org/search/", ["query": "cartoon animals", "p": String(page + 1)])
        let html = String(decoding: try await fetch(search), as: UTF8.self)
        let links = matches(#"href=["'](/detail/([0-9]+)/[^"']+)["']"#, html)
        var seen = Set<String>()
        var results: [ReservoirImage] = []
        for link in links where seen.insert(link[1]).inserted {
            let source = URL(string: "https://openclipart.org" + link[0])!
            let detail = String(decoding: try await fetch(source), as: UTF8.self)
            guard let title = matches("<h2>(.*?)</h2>", detail).first?.first,
                  !title.lowercased().contains("request"), !title.lowercased().contains("found"),
                  let author = matches(#"href=["']/artist/[^"']+["']>(.*?)</a>"#, detail).first?.first,
                  detail.contains(#"Safe for Work?</dt> <dd class="col-sm-9">Yes</dd>"#),
                  !["ai-generated", "midjourney", "stable diffusion"].contains(where: detail.lowercased().contains),
                  let imagePath = matches(#"href=["'](/image/2000px/[0-9]+)["']"#, detail).first?.first else { continue }
            results.append(ReservoirImage(id: "openclipart-" + link[1], title: clean(title), author: clean(author), source: source,
                download: URL(string: "https://openclipart.org" + imagePath)!, license: "CC0 1.0", licenseURL: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!, provider: "Openclipart"))
            if results.count >= 20 { break }
        }
        return results
    }
}
