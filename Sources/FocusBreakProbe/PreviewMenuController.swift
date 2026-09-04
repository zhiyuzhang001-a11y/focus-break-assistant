import AppKit

@MainActor
final class PreviewMenuController: NSObject {
    private let statusItem: NSStatusItem
    private var currentOverlay: HorizonOverlay?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = Self.menuBarImage()
        statusItem.button?.toolTip = "Focus Break Assistant"

        let menu = NSMenu()
        let previewItem = NSMenuItem(
            title: "预览一次提醒",
            action: #selector(previewReminder),
            keyEquivalent: ""
        )
        previewItem.target = self
        menu.addItem(previewItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出预览",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func previewReminder() {
        _ = showPreview()
    }

    func showPreview() -> HorizonOverlay? {
        guard currentOverlay == nil, let screen = activeScreen() else { return nil }
        let overlay = HorizonOverlay(screen: screen, textVariant: .fourteen)
        currentOverlay = overlay
        overlay.show(terminateApplicationOnCompletion: false) { [weak self] in
            self?.currentOverlay = nil
        }
        return overlay
    }

    var hasStatusItemButton: Bool {
        statusItem.button != nil
    }

    var hasTemplateIcon: Bool {
        statusItem.button?.image?.isTemplate == true
    }

    var menuItemTitles: [String] {
        statusItem.menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func activeScreen() -> NSScreen? {
        let activeDisplayID = MacSignalCollector().snapshot().activeDisplayID
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                == activeDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: 2.5, y: 9))
            path.line(to: NSPoint(x: 7.2, y: 9))
            path.move(to: NSPoint(x: 10.8, y: 9))
            path.line(to: NSPoint(x: 15.5, y: 9))
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
