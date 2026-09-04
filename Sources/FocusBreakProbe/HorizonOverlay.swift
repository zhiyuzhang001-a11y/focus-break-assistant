import AppKit
import FocusBreakProbeCore

enum HorizonTextVariant: String, CaseIterable {
    case thirteen = "13"
    case fourteen = "14"

    var pointSize: CGFloat {
        switch self {
        case .thirteen: 13
        case .fourteen: 14
        }
    }
}

@MainActor
final class HorizonPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HorizonOverlay {
    private let panel: HorizonPanel
    private let textVariant: HorizonTextVariant

    init(screen: NSScreen, textVariant: HorizonTextVariant = .fourteen) {
        self.textVariant = textVariant
        let size = NSSize(width: 252, height: 76)
        let visible = RectSnapshot(
            x: Double(screen.visibleFrame.origin.x),
            y: Double(screen.visibleFrame.origin.y),
            width: Double(screen.visibleFrame.width),
            height: Double(screen.visibleFrame.height)
        )
        let origin = GeometryPolicy.overlayOrigin(
            size: (Double(size.width), Double(size.height)),
            visibleFrame: visible
        )
        panel = HorizonPanel(
            contentRect: NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = HorizonView(
            frame: NSRect(origin: .zero, size: size),
            textVariant: textVariant
        )
    }

    func show(
        fadeIn: TimeInterval = 0.7,
        hold: TimeInterval = 4.8,
        fadeOut: TimeInterval = 1.1,
        terminateApplicationOnCompletion: Bool = true,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayAccessibilityPolicy.animationDuration(
                requested: fadeIn,
                options: NSWorkspace.shared.displayAccessibilityOptions
            )
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = OverlayAccessibilityPolicy.animationDuration(
                        requested: fadeOut,
                        options: NSWorkspace.shared.displayAccessibilityOptions
                    )
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.panel.animator().alphaValue = 0
                } completionHandler: {
                    Task { @MainActor in
                        self.panel.orderOut(nil)
                        onDismiss?()
                        if terminateApplicationOnCompletion {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
            }
        }
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
            textPointSize: Double(textVariant.pointSize)
        )
    }

    static func renderVisualMatrix(to outputDirectory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        var outputs: [URL] = []
        for environment in HorizonPreviewEnvironment.allCases {
            for variant in HorizonTextVariant.allCases {
                let canvas = HorizonPreviewCanvas(
                    frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
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
                    .appendingPathComponent("\(environment.rawValue)-\(variant.rawValue)pt.png")
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

    override var isFlipped: Bool { true }

    init(frame frameRect: NSRect, textVariant: HorizonTextVariant = .fourteen) {
        self.textVariant = textVariant
        super.init(frame: frameRect)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        textVariant = .fourteen
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
        let background = isDark
            ? NSColor(
                calibratedWhite: 0.10,
                alpha: OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.86, options: displayOptions)
            )
            : NSColor(
                calibratedRed: 0.97,
                green: 0.96,
                blue: 0.93,
                alpha: OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.88, options: displayOptions)
            )
        let textColor = isDark
            ? NSColor(calibratedWhite: increaseContrast ? 1 : 0.93, alpha: 1)
            : NSColor(calibratedWhite: increaseContrast ? 0.08 : 0.18, alpha: 1)
        let lineColor = isDark
            ? NSColor(calibratedRed: 0.55, green: 0.70, blue: 0.71, alpha: 1)
            : NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.37, alpha: 1)

        background.setFill()
        let surface = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        surface.fill()
        if OverlayAccessibilityPolicy.showsOutline(options: displayOptions) {
            textColor.withAlphaComponent(0.55).setStroke()
            surface.lineWidth = 1
            surface.stroke()
        }

        lineColor.setStroke()
        let line = NSBezierPath()
        line.lineWidth = OverlayAccessibilityPolicy.lineWidth(options: displayOptions)
        line.move(to: NSPoint(x: 72, y: 18.5))
        line.line(to: NSPoint(x: 122, y: 18.5))
        line.move(to: NSPoint(x: 132, y: 18.5))
        line.line(to: NSPoint(x: 182, y: 18.5))
        line.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: textVariant.pointSize, weight: .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let message = "给下一段留一点余白。\n让目光去远处停一会儿。"
        message.draw(
            in: NSRect(x: 12, y: 30, width: bounds.width - 24, height: 42),
            withAttributes: attributes
        )
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

        let overlaySize = NSSize(width: 252, height: 76)
        let origin = GeometryPolicy.overlayOrigin(
            size: (Double(overlaySize.width), Double(overlaySize.height)),
            visibleFrame: RectSnapshot(x: 0, y: 25, width: 1440, height: 850)
        )
        addSubview(HorizonView(
            frame: NSRect(x: origin.x, y: origin.y, width: overlaySize.width, height: overlaySize.height),
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
