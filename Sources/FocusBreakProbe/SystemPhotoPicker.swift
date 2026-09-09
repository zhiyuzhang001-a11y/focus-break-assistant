import AppKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import CryptoKit

/// Copies only files explicitly returned by the system picker, never traverses a Photos library.
enum PhotoImportStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusBreakAssistant/ImportedPhotos", isDirectory: true)
    }

    static func importFile(_ sourceURL: URL, into directory: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let type = CGImageSourceGetType(source),
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
              ] as CFDictionary) != nil else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        let key = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let imageType = type as String
        let extensions = [UTType.jpeg.identifier: "jpg", UTType.png.identifier: "png", UTType.heic.identifier: "heic"]
        let destination = directory.appendingPathComponent(key).appendingPathExtension(extensions[imageType] ?? "jpg")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).import")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if extensions[imageType] != nil {
            try FileManager.default.copyItem(at: sourceURL, to: temporary)
        } else {
            guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImageFromSource(output, source, 0, nil)
            guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

@MainActor
final class SystemPhotoPicker: NSObject, PHPickerViewControllerDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var importing = false
    private let completion: (Int, Int) -> Void
    private let progressLabel = NSTextField(labelWithString: "正在导入照片…")

    init(completion: @escaping (Int, Int) -> Void) { self.completion = completion }

    func bringToFront() {
        NSApp.setActivationPolicy(.accessory)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        let window = NSWindow(contentViewController: picker)
        window.title = "从系统照片图库选择"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 560, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !importing }

    func windowWillClose(_ notification: Notification) {
        guard !importing else { return }
        completion(0, 0)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard !importing else { return }
        guard !results.isEmpty else { window?.close(); return }
        importing = true
        window?.standardWindowButton(.closeButton)?.isEnabled = false
        let viewController = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 620))
        viewController.view = view
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLabel)
        NSLayoutConstraint.activate([
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        window?.contentViewController = viewController
        Task { @MainActor in
            var imported = 0
            var failed = 0
            for (index, result) in results.enumerated() {
                progressLabel.stringValue = "正在导入 \(index + 1) / \(results.count)… iCloud 照片可能需要下载。"
                let provider = result.itemProvider
                let type = provider.registeredTypeIdentifiers.first {
                    UTType($0)?.conforms(to: .image) == true
                }
                guard let type else { failed += 1; continue }
                let success: Bool = await withCheckedContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                        guard let url else { continuation.resume(returning: false); return }
                        // The provider's temporary file is valid only inside this callback.
                        do {
                            _ = try PhotoImportStore.importFile(url, into: PhotoImportStore.directory)
                            continuation.resume(returning: true)
                        } catch { continuation.resume(returning: false) }
                    }
                }
                if success { imported += 1 } else { failed += 1 }
            }
            window?.delegate = nil
            window?.close()
            completion(imported, failed)
        }
    }
}
