import AppKit
import FocusBreakProbeCore

@MainActor
func renderReservoirReview() throws -> [String: Int] {
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/reservoir-review")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let store = OnlineReservoir.shared.store
    var decoded: [String: Int] = [:]
    for category in ImageCategory.allCases {
        guard let batch = store.batch(category) else { decoded[category.rawValue] = 0; continue }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 480, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1400, height: 480).fill()
        var count = 0
        for (i, item) in batch.images.enumerated() {
            guard let image = PhotoLibrary.decode(store.file(item, batch: batch, category: category)) else { continue }
            count += 1
            let box = NSRect(x: (i % 5) * 280 + 8, y: 480 - (i / 5 + 1) * 240 + 35, width: 264, height: 196)
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
            let title = "\(i + 1). \(item.title)"
            (title as NSString).draw(in: NSRect(x: box.minX, y: box.minY - 29, width: 264, height: 26), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(category.rawValue + ".png"))
        decoded[category.rawValue] = count
    }
    return decoded
}
