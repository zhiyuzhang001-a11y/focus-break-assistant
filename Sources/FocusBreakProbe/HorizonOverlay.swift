import AppKit
import FocusBreakProbeCore

enum HorizonTextVariant: String, CaseIterable {
    case standard = "32"
    case prominent = "36"

    var pointSize: CGFloat {
        switch self {
        case .standard: 32
        case .prominent: 36
        }
    }
}

private enum HorizonStyle {
    static func frame(in visible: NSRect) -> NSRect {
        let frame = ResponsiveLayoutPolicy.frame(in: RectSnapshot(
            x: visible.origin.x, y: visible.origin.y, width: visible.width, height: visible.height))
        return NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    static let cornerRadius: CGFloat = 24
}

@MainActor
final class HorizonPanel: NSPanel {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    var acceptsInteraction = false
    override var canBecomeKey: Bool { acceptsInteraction }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HorizonOverlay: NSObject {
    private var completion: (@MainActor () -> Void)?
    private var breakAction: (() -> Void)?
    private var favoriteButton: NSButton?
    private let selectedPhoto: LibraryPhoto?
    private var snoozeAction: (() -> Void)?
    private var skipAction: (() -> Void)?
    private var escapeMonitor: Any?
    private var isDismissed = false
    private let panel: HorizonPanel
    private let destinationFrame: NSRect
    private let curtainMask = CALayer()
    private let textVariant: HorizonTextVariant

    init(screen: NSScreen, textVariant: HorizonTextVariant = .prominent, selectedPhoto: LibraryPhoto? = nil) {
        self.textVariant = textVariant
        let photo = selectedPhoto ?? PhotoLibrary.shared.nextPhoto()
        self.selectedPhoto = photo
        let visible = screen.visibleFrame
        let fitted = ResponsiveLayoutPolicy.imageFrame(
            in: RectSnapshot(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
            sourceWidth: Double(photo?.image.size.width ?? 0), sourceHeight: Double(photo?.image.size.height ?? 0))
        let frame = NSRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height)
        destinationFrame = frame
        let size = frame.size
        panel = HorizonPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = HorizonView(
            frame: NSRect(origin: .zero, size: size),
            textVariant: textVariant,
            selectedPhoto: photo, allowFallbackArtwork: false
        )
    }

    var onTimeout: (@MainActor () -> Void)?

    func show(
        fadeIn: TimeInterval = 2.8,
        hold: TimeInterval = 5.0,
        fadeOut: TimeInterval = 0.8,
        terminateApplicationOnCompletion: Bool = true,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        completion = onDismiss
        let options = NSWorkspace.shared.displayAccessibilityOptions
        let duration = OverlayAccessibilityPolicy.animationDuration(requested: fadeIn, options: options)
        panel.setFrame(destinationFrame, display: false)
        panel.alphaValue = options.reduceMotion ? 0 : 1
        if let view = panel.contentView {
            view.wantsLayer = true
            view.displayIfNeeded()
            if let layer = view.layer {
                let top: CGFloat = layer.isGeometryFlipped ? 0 : 1
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                curtainMask.backgroundColor = NSColor.black.cgColor
                curtainMask.anchorPoint = CGPoint(x: 0.5, y: top)
                curtainMask.bounds = CGRect(origin: .zero, size: view.bounds.size)
                curtainMask.position = CGPoint(x: view.bounds.midX, y: view.bounds.height * top)
                layer.mask = curtainMask
                CATransaction.commit()
            }
        }
        if panel.acceptsInteraction { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        if options.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = 1
            }
        } else {
            // The image stays fixed. Only the mask's bottom edge descends.
            let reveal = CABasicAnimation(keyPath: "bounds.size.height")
            reveal.fromValue = 0
            reveal.toValue = destinationFrame.height
            reveal.duration = duration
            reveal.beginTime = curtainMask.convertTime(CACurrentMediaTime(), from: nil)
            reveal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            curtainMask.add(reveal, forKey: "curtainReveal")
            CATransaction.flush()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + hold) { [weak self] in
            guard let self, !self.isDismissed else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayAccessibilityPolicy.animationDuration(
                    requested: fadeOut,
                    options: NSWorkspace.shared.displayAccessibilityOptions
                )
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    guard !self.isDismissed else { return }
                    self.onTimeout?()
                    self.dismiss()
                    if terminateApplicationOnCompletion {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }

    func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        curtainMask.removeAllAnimations()
        panel.orderOut(nil)
        let callback = completion; completion = nil
        callback?()
    }

    func addControls(snooze: (() -> Void)?, skip: (() -> Void)?, beginBreak: (() -> Void)? = nil) {
        snoozeAction = snooze; skipAction = skip; breakAction = beginBreak
        panel.ignoresMouseEvents = false
        panel.acceptsInteraction = true
        panel.onEscape = { [weak self] in self?.dismiss() }
        let compact = destinationFrame.width < 540 || destinationFrame.height < 270
        let actions: [(String, Selector)] = (beginBreak == nil ? [] : [("开始休息", #selector(startBreak))]) +
            (snooze == nil ? [] : [("稍后 5 分钟", #selector(snoozeReminder)), ("跳过本次", #selector(skipReminder))]) +
            [("收起 · Esc", #selector(closeReminder))]
        let feedback: [(String, Selector)] = selectedPhoto?.fileURL == nil ? [] :
            [(PhotoCuration.shared.isFavorite(selectedPhoto!) ? "已收藏" : "收藏", #selector(favoritePhoto)),
             ("不要再显示这张", #selector(blockPhoto))]
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        if compact {
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.addItem(withTitle: "提醒操作")
            for (title, action) in actions + feedback {
                popup.menu?.addItem(withTitle: title, action: action, keyEquivalent: "")
                popup.menu?.items.last?.target = self
            }
            stack.addArrangedSubview(popup)
        } else {
            for row in [actions, feedback] where !row.isEmpty {
                let group = NSStackView(); group.orientation = .horizontal; group.spacing = 12
                for (title, action) in row {
                    let button = NSButton(title: title, target: self, action: action)
                    if action == #selector(favoritePhoto) { favoriteButton = button }
                    group.addArrangedSubview(button)
                }
                stack.addArrangedSubview(group)
            }
        }
        if let view = panel.contentView {
            (view as? HorizonView)?.controlInset = compact ? 48 : 88
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
            ])
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, event.window === self.panel { self.dismiss(); return nil }
            return event
        }
    }

    private func feedback(_ action: () throws -> Void) {
        do { try action() }
        catch {
            let alert = NSAlert(error: error)
            alert.messageText = "未能保存图片偏好"
            alert.informativeText = "原图未被改动。请检查本机可用空间和收藏目录后重试。"
            alert.beginSheetModal(for: panel)
        }
    }
    @objc private func favoritePhoto() {
        guard let selectedPhoto else { return }
        feedback { try PhotoCuration.shared.favorite(selectedPhoto); favoriteButton?.title = "已收藏" }
    }
    @objc private func blockPhoto() {
        guard let selectedPhoto else { return }
        feedback { try PhotoCuration.shared.block(selectedPhoto); dismiss() }
    }
    @objc private func startBreak() { breakAction?(); dismiss() }
    @objc private func closeReminder() { dismiss() }
    @objc private func snoozeReminder() { snoozeAction?(); dismiss() }
    @objc private func skipReminder() { skipAction?(); dismiss() }

    func curtainSample() -> [String: Double] {
        let visibleMask = curtainMask.presentation() ?? curtainMask
        return [
            "visibleHeight": Double(visibleMask.bounds.height),
            "fullHeight": Double(destinationFrame.height),
            "maskTop": Double(visibleMask.position.y),
            "windowY": Double(panel.frame.origin.y),
            "windowHeight": Double(panel.frame.height)
        ]
    }

    func verification(
        frontmostPIDBefore: pid_t?,
        frontmostPIDAfter: pid_t?
    ) -> OverlayVerification {
        let workspace = NSWorkspace.shared
        let appearance = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "dark"
            : "light"
        return OverlayVerification(
            frontmostPIDBefore: frontmostPIDBefore,
            frontmostPIDAfter: frontmostPIDAfter,
            frontmostApplicationUnchanged: frontmostPIDBefore != nil && frontmostPIDBefore == frontmostPIDAfter,
            ignoresMouseEvents: panel.ignoresMouseEvents,
            canBecomeKey: panel.canBecomeKey,
            canBecomeMain: panel.canBecomeMain,
            isKeyWindow: panel.isKeyWindow,
            isMainWindow: panel.isMainWindow,
            windowLevel: Int(panel.level.rawValue),
            reduceMotionEnabled: workspace.accessibilityDisplayShouldReduceMotion,
            increaseContrastEnabled: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparencyEnabled: workspace.accessibilityDisplayShouldReduceTransparency,
            effectiveAppearance: appearance,
            textPointSize: Double((panel.contentView as? HorizonView)?.effectivePointSize ?? textVariant.pointSize)
        )
    }

    static func renderVisualMatrix(to outputDirectory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        var outputs: [URL] = []
        let scenarios = HorizonPreviewEnvironment.allCases.map {
            ($0.rawValue, $0, NSSize(width: 1440, height: 900))
        } + [
            ("small-screen", .lightDesktop, NSSize(width: 800, height: 600)),
            ("portrait-screen", .lightDesktop, NSSize(width: 900, height: 1600)),
            ("ultrawide-screen", .lightDesktop, NSSize(width: 2560, height: 1080)),
            ("large-screen", .lightDesktop, NSSize(width: 2560, height: 1440))
        ]
        for (name, environment, screenSize) in scenarios {
            for variant in HorizonTextVariant.allCases {
                let canvas = HorizonPreviewCanvas(
                    frame: NSRect(origin: .zero, size: screenSize),
                    environment: environment,
                    textVariant: variant
                )
                canvas.layoutSubtreeIfNeeded()
                guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
                    throw HorizonPreviewError.couldNotCreateBitmap
                }
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw HorizonPreviewError.couldNotEncodePNG
                }
                let url = outputDirectory
                    .appendingPathComponent("\(name)-\(variant.rawValue)pt.png")
                try png.write(to: url, options: .atomic)
                outputs.append(url)
            }
        }
        return outputs
    }
}

@MainActor
private final class HorizonView: NSView {
    private let textVariant: HorizonTextVariant
    private static let photo: PhotoPlacement = {
        guard let url = Bundle.module.url(forResource: "Photo", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let photo = try? JSONDecoder().decode(PhotoPlacement.self, from: data) else {
            return PhotoPlacement(resourceName: "Seascape", focalX: 0.5, focalY: 0.52)
        }
        return photo
    }()
    private let artwork: NSImage?
    private let focalX: Double
    private let focalY: Double
    var controlInset: CGFloat = 0

    var effectivePointSize: CGFloat {
        ResponsiveLayoutPolicy.fontSize(base: textVariant.pointSize, width: bounds.width, height: bounds.height)
    }

    override var isFlipped: Bool { true }

    init(frame frameRect: NSRect, textVariant: HorizonTextVariant = .prominent, selectedPhoto: LibraryPhoto? = nil, allowFallbackArtwork: Bool = true) {
        self.textVariant = textVariant
        artwork = selectedPhoto?.image ?? (allowFallbackArtwork ? Self.loadImage(named: Self.photo.resourceName) : nil)
        focalX = selectedPhoto?.focalX ?? Self.photo.focalX
        focalY = selectedPhoto?.focalY ?? Self.photo.focalY
        super.init(frame: frameRect)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        textVariant = .prominent
        artwork = Self.loadImage(named: Self.photo.resourceName)
        focalX = Self.photo.focalX
        focalY = Self.photo.focalY
        super.init(coder: coder)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let workspace = NSWorkspace.shared
        let displayOptions = workspace.displayAccessibilityOptions
        let increaseContrast = displayOptions.increaseContrast
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fallbackBackground = isDark
            ? NSColor(
                calibratedRed: 0.34,
                green: 0.29,
                blue: 0.26,
                alpha: OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.94, options: displayOptions)
            )
            : NSColor(
                calibratedRed: 0.82,
                green: 0.75,
                blue: 0.65,
                alpha: OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.94, options: displayOptions)
            )
        let textColor = isDark
            ? NSColor(calibratedWhite: increaseContrast ? 1 : 0.96, alpha: 1)
            : NSColor(calibratedWhite: increaseContrast ? 0.06 : 0.15, alpha: 1)

        let surface = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: HorizonStyle.cornerRadius,
            yRadius: HorizonStyle.cornerRadius
        )
        NSGraphicsContext.saveGraphicsState()
        surface.addClip()
        fallbackBackground.setFill()
        surface.fill()

        if let image = artwork {
            let fitted = ResponsiveLayoutPolicy.photoDestination(
                sourceWidth: image.size.width, sourceHeight: image.size.height,
                targetWidth: bounds.width, targetHeight: bounds.height)
            let destination = NSRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height)
            image.draw(
                in: destination,
                from: image.sourceRect(aspectFilling: destination.size, focalX: focalX, focalY: focalY),
                operation: .sourceOver,
                fraction: OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.94, options: displayOptions),
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            (isDark
                ? NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.10, alpha: 0.28)
                : NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.54, alpha: 0.08)
            ).setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if OverlayAccessibilityPolicy.showsOutline(options: displayOptions) {
            textColor.withAlphaComponent(0.55).setStroke()
            surface.lineWidth = OverlayAccessibilityPolicy.lineWidth(options: displayOptions)
            surface.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = effectivePointSize / 3
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        textShadow.shadowBlurRadius = 3
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: effectivePointSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: textShadow,
            .paragraphStyle: paragraph
        ]
        let presentation = ReminderPresentation()
        let message = bounds.height - controlInset < effectivePointSize * 4 ? "歇一会儿" : presentation.message
        let textWidth = min(max(1, bounds.width - 48), effectivePointSize * 20)
        let textHeight = ceil((message as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height)
        let usableHeight = max(textHeight, bounds.height - controlInset - 16)
        let y = presentation.position == .bottom ? usableHeight - textHeight : (usableHeight - textHeight) / 2
        let textRect = NSRect(x: bounds.midX - textWidth / 2,
                              y: max(8, y),
                              width: textWidth, height: textHeight)
        (message as NSString).draw(with: textRect,
                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                  attributes: attributes)
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct PhotoPlacement: Decodable {
    let resourceName: String
    let focalX: Double
    let focalY: Double
}

private extension NSImage {
    func sourceRect(aspectFilling destinationSize: NSSize, focalX: Double, focalY: Double) -> NSRect {
        let crop = ResponsiveLayoutPolicy.crop(
            sourceWidth: size.width, sourceHeight: size.height,
            targetWidth: destinationSize.width, targetHeight: destinationSize.height,
            focalX: focalX, focalY: focalY)
        return NSRect(x: crop.x, y: size.height - crop.y - crop.height,
                      width: crop.width, height: crop.height)
    }
}

private enum HorizonPreviewError: Error {
    case couldNotCreateBitmap
    case couldNotEncodePNG
}

private enum HorizonPreviewEnvironment: String, CaseIterable {
    case lightDesktop = "light-desktop"
    case darkDesktop = "dark-desktop"
    case complexWallpaper = "complex-wallpaper"
    case codeEditor = "code-editor"
    case notificationCoexistence = "notification-coexistence"

    var appearanceName: NSAppearance.Name {
        switch self {
        case .lightDesktop: .aqua
        case .darkDesktop, .complexWallpaper, .codeEditor, .notificationCoexistence: .darkAqua
        }
    }
}

@MainActor
private final class HorizonPreviewCanvas: NSView {
    private let environment: HorizonPreviewEnvironment

    init(frame frameRect: NSRect, environment: HorizonPreviewEnvironment, textVariant: HorizonTextVariant) {
        self.environment = environment
        super.init(frame: frameRect)
        appearance = NSAppearance(named: environment.appearanceName)

        let overlayFrame = HorizonStyle.frame(in: NSRect(x: 0, y: 25, width: bounds.width, height: bounds.height - 50))
        addSubview(HorizonView(
            frame: overlayFrame,
            textVariant: textVariant
        ))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch environment {
        case .lightDesktop:
            NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.87, alpha: 1).setFill()
            bounds.fill()
            drawWindow(in: NSRect(x: 90, y: 90, width: 1040, height: 690), dark: false)
        case .darkDesktop:
            NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.13, alpha: 1).setFill()
            bounds.fill()
            drawWindow(in: NSRect(x: 110, y: 80, width: 1010, height: 700), dark: true)
        case .complexWallpaper:
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.22, alpha: 1),
                NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.29, alpha: 1),
                NSColor(calibratedRed: 0.14, green: 0.30, blue: 0.27, alpha: 1)
            ])
            gradient?.draw(in: bounds, angle: -18)
            for (rect, color) in [
                (NSRect(x: 120, y: 120, width: 540, height: 540), NSColor.white.withAlphaComponent(0.08)),
                (NSRect(x: 720, y: 70, width: 610, height: 610), NSColor.black.withAlphaComponent(0.12)),
                (NSRect(x: 460, y: 410, width: 520, height: 380), NSColor.systemTeal.withAlphaComponent(0.10))
            ] {
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        case .codeEditor:
            NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.10, alpha: 1).setFill()
            bounds.fill()
            NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 245, height: bounds.height).fill()
            drawCodeLines()
        case .notificationCoexistence:
            NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.14, alpha: 1).setFill()
            bounds.fill()
            drawWindow(in: NSRect(x: 90, y: 80, width: 1030, height: 700), dark: true)
            drawNotificationReference()
        }
    }

    private func drawWindow(in rect: NSRect, dark: Bool) {
        (dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        (dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.88, alpha: 1)).setFill()
        NSRect(x: rect.minX, y: rect.maxY - 46, width: rect.width, height: 46).fill()
    }

    private func drawCodeLines() {
        let colors = [NSColor.systemTeal, .systemPurple, .systemOrange, .systemGray]
        for index in 0..<22 {
            let indent = CGFloat((index * 29) % 150)
            let width = CGFloat(180 + (index * 71) % 510)
            colors[index % colors.count].withAlphaComponent(0.55).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 295 + indent, y: 785 - CGFloat(index * 31), width: width, height: 5),
                xRadius: 2.5,
                yRadius: 2.5
            ).fill()
        }
    }

    private func drawNotificationReference() {
        let rect = NSRect(x: 1084, y: 805, width: 330, height: 72)
        NSColor(calibratedWhite: 0.18, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        NSColor(calibratedWhite: 0.82, alpha: 0.8).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 18, y: rect.maxY - 27, width: 116, height: 5),
            xRadius: 2.5,
            yRadius: 2.5
        ).fill()
        NSColor(calibratedWhite: 0.62, alpha: 0.65).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 18, y: rect.minY + 17, width: 230, height: 5),
            xRadius: 2.5,
            yRadius: 2.5
        ).fill()
    }
}

private extension NSWorkspace {
    var displayAccessibilityOptions: DisplayAccessibilityOptions {
        DisplayAccessibilityOptions(
            reduceMotion: accessibilityDisplayShouldReduceMotion,
            increaseContrast: accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: accessibilityDisplayShouldReduceTransparency
        )
    }
}
