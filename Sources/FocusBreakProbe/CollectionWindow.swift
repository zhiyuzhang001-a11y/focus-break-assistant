import AppKit

@MainActor
final class CollectionWindow: NSObject, NSWindowDelegate {
    private let store: PhotoCuration
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    var onClose: (() -> Void)?
    init(store: PhotoCuration = .shared) {
        self.store = store
        super.init()
        window.title = "收藏与已屏蔽图片"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 360)
        window.delegate = self
        rebuild()
    }
    func show() { NSApp.setActivationPolicy(.accessory); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { onClose?() }
    private func rebuild() {
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let stack = SettingsStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        scroll.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        window.contentView = scroll
        func label(_ text: String) { stack.addArrangedSubview(NSTextField(wrappingLabelWithString: text)) }
        label("收藏 \(store.favorites.count) 张 · 已屏蔽 \(store.blocked.count) 张")
        label("收藏保留原始文件和来源许可，不随每日图库更新删除。取消收藏只删除保留的副本。")
        if store.loadError { label("偏好记录无法读取，已保留文件并停止写入。请检查 collection.json。") }
        for (index, entry) in store.favorites.enumerated() {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let preview = NSImageView(); preview.image = PhotoLibrary.decode(store.file(entry)); preview.imageScaling = .scaleProportionallyUpOrDown
            preview.widthAnchor.constraint(equalToConstant: 84).isActive = true
            preview.heightAnchor.constraint(equalToConstant: 64).isActive = true
            row.addArrangedSubview(preview)
            let title = NSTextField(wrappingLabelWithString: "\(entry.credit.title)\n\(entry.credit.author) · \(entry.credit.license)")
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 330).isActive = true
            row.addArrangedSubview(title)
            let remove = NSButton(title: "取消收藏", target: self, action: #selector(removeFavorite(_:))); remove.tag = index
            row.addArrangedSubview(remove); stack.addArrangedSubview(row)
        }
        if store.favorites.isEmpty { label("在提醒图片上点击“收藏”，下次可从设置切换到收藏图库。") }
        let open = NSButton(title: "打开收藏及来源记录", target: self, action: #selector(openFolder)); stack.addArrangedSubview(open)
        if !store.blocked.isEmpty {
            label("已屏蔽图片")
            for (index, entry) in store.blocked.enumerated() {
                let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
                let title = NSTextField(wrappingLabelWithString: entry.title)
                title.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
                row.addArrangedSubview(title)
                let button = NSButton(title: "恢复显示", target: self, action: #selector(restoreOne(_:))); button.tag = index
                row.addArrangedSubview(button); stack.addArrangedSubview(row)
            }
            stack.addArrangedSubview(NSButton(title: "恢复所有已屏蔽图片", target: self, action: #selector(restore)))
        }
    }
    @objc private func openFolder() {
        do { try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true); NSWorkspace.shared.open(store.root) }
        catch { NSAlert(error: error).beginSheetModal(for: window) }
    }
    @objc private func removeFavorite(_ sender: NSButton) {
        guard store.favorites.indices.contains(sender.tag) else { return }
        do { try store.removeFavorite(id: store.favorites[sender.tag].id); rebuild() }
        catch { NSAlert(error: error).beginSheetModal(for: window) }
    }
    @objc private func restoreOne(_ sender: NSButton) {
        guard store.blocked.indices.contains(sender.tag) else { return }
        do { try store.restore(id: store.blocked[sender.tag].id); rebuild() }
        catch { NSAlert(error: error).beginSheetModal(for: window) }
    }
    @objc private func restore() {
        do { try store.restoreBlocked(); rebuild() }
        catch { NSAlert(error: error).beginSheetModal(for: window) }
    }
}
