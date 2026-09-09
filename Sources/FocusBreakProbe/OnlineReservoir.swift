import AppKit
import FocusBreakProbeCore

@MainActor
final class OnlineReservoir {
    static let shared = OnlineReservoir()
    let store: ImageReservoir
    private let defaults: UserDefaults
    private let candidateLoader: (ImageCategory, Int, String) async throws -> [ReservoirImage]
    private let downloadLoader: (ReservoirImage) async throws -> Data
    private let curation: PhotoCuration
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var manualFeedback: ((String) -> Void)?
    private(set) var status = "每类保持 10 张 · 无需密钥" { didSet { manualFeedback?(status) } }
    private(set) var currentImage: ReservoirImage?
    private var generation = 0
    init(defaults: UserDefaults = .standard, root: URL? = nil, curation: PhotoCuration? = nil,
         candidates: ((ImageCategory, Int, String) async throws -> [ReservoirImage])? = nil,
         download: ((ReservoirImage) async throws -> Data)? = nil) {
        let provider = ReservoirProvider()
        candidateLoader = candidates ?? { try await provider.candidates($0, page: $1, peopleStyle: $2) }
        downloadLoader = download ?? { try await provider.download($0) }
        self.defaults = defaults
        self.curation = curation ?? root.map { PhotoCuration(root: $0.appendingPathComponent("TestCollection")) } ?? .shared
        store = ImageReservoir(root: root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant/OnlineReservoir"))
    }
    var enabled: Bool { defaults.object(forKey: "reservoirEnabled") as? Bool ?? true }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 60
    }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "reservoirEnabled")
        if enabled { refresh() }
        else { generation += 1; task?.cancel(); status = "更新已暂停，保留全部现有图片" }
    }
    func refresh(manual: Bool = false, feedback: ((String) -> Void)? = nil) {
        if task != nil {
            if manual { manualFeedback = feedback; feedback?("已有检查正在进行 · " + status) }
            return
        }
        guard enabled || manual else { return }
        manualFeedback = manual ? feedback : nil
        status = "正在检查六类图库…"
        task = Task { [weak self] in
            guard let self else { return }
            await self.updateAll(manual: manual)
            self.task = nil
            self.manualFeedback = nil
        }
    }
    func updateAll(now: Date = Date(), calendar: Calendar = .current, manual: Bool = false) async {
        guard enabled || manual else { return }
        let token = generation
        var failed: [String] = []
        var updated = 0
        for category in ImageCategory.allCases {
            guard token == generation, !Task.isCancelled else { return }
            if let batch = store.batch(category), calendar.isDate(batch.updatedAt, inSameDayAs: now) { continue }
            if !manual, let attempt = defaults.object(forKey: "reservoirAttempt." + category.rawValue) as? Date,
               now.timeIntervalSince(attempt) < 3600 { failed.append(category.title); continue }
            defaults.set(now, forKey: "reservoirAttempt." + category.rawValue)
            do { try await update(category, token: token); updated += 1 }
            catch { failed.append(category.title); status = "\(category.title)更新未完成，保留原有图库" }
        }
        let total = ImageCategory.allCases.reduce(0) { $0 + (store.batch($1)?.images.count ?? 0) }
        guard token == generation else { return }
        if !failed.isEmpty { status = "检查未完成，保留旧图；可手动重试：" + failed.joined(separator: "、") }
        else if updated == 0 { status = "检查完成 · 今天的图库已是最新（\(total)/60 张），无需重复下载" }
        else { status = "检查完成 · 已更新 \(updated) 类，图库 \(total)/60 张" }
    }
    func update(_ category: ImageCategory, token: Int = 0) async throws {
        let lock = ReservoirFileLock()
        guard try lock.acquire(root: store.root) else { throw CocoaError(.fileLocking) }
        defer { lock.release() }
        for item in ImageCategory.allCases { try store.repair(item) }
        let stage = try store.begin(category)
        defer { try? store.repair(category) }
        let previous = Set(store.batch(category)?.images.map(\.id) ?? [])
        var images: [ReservoirImage] = []
        var seen = previous
        var acceptedHashes: [UInt64] = []
        var acceptedSubjects = Set<String>()
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        for offset in 0..<5 {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            let page = store.batch(category) == nil ? offset : (day + offset) % 5
            status = "\(category.title)：正在准备 \(images.count)/10 张"
            let candidates = try await candidateLoader(category, page, ImagePreferences(defaults: defaults).peopleStyle)
            for image in candidates where !seen.contains(image.id) && !curation.isBlocked(id: image.id) {
                seen.insert(image.id)
                try Task.checkCancellation()
                guard token == generation else { throw CancellationError() }
                do {
                    let data = try await downloadLoader(image)
                    try Task.checkCancellation()
                    guard token == generation else { throw CancellationError() }
                    guard let signature = PhotoCuration.signature(data),
                          !curation.isBlocked(id: image.id, digest: signature.digest),
                          !acceptedHashes.contains(where: { PhotoCuration.similar($0, signature.hash) }) else { continue }
                    let subject = PhotoCuration.subject(image.title)
                    guard !acceptedSubjects.contains(subject) else { continue }
                    try store.append(data, image: image, stage: stage)
                    acceptedHashes.append(signature.hash)
                    acceptedSubjects.insert(subject)
                    images.append(image)
                    status = "\(category.title)：正在准备 \(images.count)/10 张"
                    if images.count == ImageReservoir.count {
                        try store.commit(images, stage: stage, category: category)
                        status = "\(category.title)：10 张已就绪"
                        return
                    }
                } catch is CancellationError { throw CancellationError() }
                catch ReservoirProvider.Failure.response(let code) where code == 429 { throw ReservoirProvider.Failure.response(code) }
                catch { continue }
            }
        }
        throw ReservoirProvider.Failure.invalid
    }
    func files(_ category: ImageCategory) -> [URL] {
        guard let batch = store.batch(category) else { return [] }
        return batch.images.map { store.file($0, batch: batch, category: category) }
    }
    func metadata(_ file: URL) -> ReservoirImage? {
        for category in ImageCategory.allCases {
            guard let batch = store.batch(category) else { continue }
            if let image = batch.images.first(where: { store.file($0, batch: batch, category: category) == file }) { return image }
        }
        return nil
    }
    func recordSource(_ file: URL) { currentImage = metadata(file) }
}

extension ReservoirImage {
    var credit: PhotoCuration.Credit {
        PhotoCuration.Credit(title: title, author: author, source: source.absoluteString, license: license, licenseURL: licenseURL.absoluteString)
    }
}
