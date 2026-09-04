import AppKit
import ApplicationServices
import CoreGraphics
import FocusBreakProbeCore

@MainActor
final class MacSignalCollector {
    private static let anyInputEventType = CGEventType(rawValue: UInt32.max)!
    private(set) var sessionInactive = false
    private(set) var systemSleeping = false

    private var observers: [NSObjectProtocol] = []
    private let useAccessibility: Bool

    init(
        useAccessibility: Bool = true,
        eventSink: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.useAccessibility = useAccessibility
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionInactive = true
            eventSink("session_switched_out")
        }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionInactive = false
            eventSink("session_switched_in")
        }
        observe(center, NSWorkspace.willSleepNotification) { [weak self] in
            self?.systemSleeping = true
            eventSink("system_will_sleep")
        }
        observe(center, NSWorkspace.didWakeNotification) { [weak self] in
            self?.systemSleeping = false
            eventSink("system_did_wake")
        }
        observe(center, NSWorkspace.screensDidSleepNotification) {
            eventSink("display_sleep_notification")
        }
        observe(center, NSWorkspace.screensDidWakeNotification) {
            eventSink("display_wake_notification")
        }
    }

    func snapshot() -> ProbeSnapshot {
        let displays = Self.displaySnapshots()
        let accessibilityTrusted = AXIsProcessTrusted()
        let accessibilityEnabled = accessibilityTrusted && useAccessibility
        let accessibilityFrame = accessibilityEnabled ? Self.focusedWindowFrame() : nil
        let windowServerFrame = Self.frontmostWindowFrameFromWindowServer()
        let focusedFrame = accessibilityFrame ?? windowServerFrame

        let selectedDisplay: DisplaySnapshot?
        let source: String
        if let focusedFrame,
           let display = GeometryPolicy.displayWithLargestIntersection(window: focusedFrame, displays: displays) {
            selectedDisplay = display
            source = accessibilityFrame != nil ? "focused_window_accessibility" : "frontmost_window_bounds"
        } else {
            let pointer = CGEvent(source: nil)?.location ?? .zero
            selectedDisplay = GeometryPolicy.displayContaining(
                point: (Double(pointer.x), Double(pointer.y)),
                displays: displays
            ) ?? displays.first(where: \.isMain)
            source = "pointer_fallback"
        }

        let fullScreen: TriState
        if accessibilityEnabled,
           let focusedWindow = Self.focusedWindowElement() {
            fullScreen = Self.fullScreenState(window: focusedWindow, frame: focusedFrame, display: selectedDisplay)
        } else if let focusedFrame, let selectedDisplay {
            fullScreen = GeometryPolicy.isFullScreen(
                window: focusedFrame,
                display: selectedDisplay.frame
            ) ? .yes : .no
        } else {
            fullScreen = .unknown
        }

        return ProbeSnapshot(
            capturedAt: Date(),
            idleSeconds: Self.idleSeconds(),
            sessionInactive: sessionInactive,
            systemSleeping: systemSleeping,
            displaySleepState: Self.displaySleepState(),
            accessibilityTrusted: accessibilityTrusted,
            activeDisplayID: selectedDisplay?.id,
            activeDisplaySource: source,
            focusedWindowFullScreen: fullScreen,
            displays: displays
        )
    }

    func activitySnapshot() -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: Date(),
            idleSeconds: Self.idleSeconds(),
            sessionInactive: sessionInactive,
            systemSleeping: systemSleeping,
            displaySleepState: Self.displaySleepState()
        )
    }

    func idleSignalVerification() -> IdleSignalVerification {
        let hidAny = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: Self.anyInputEventType
        )
        let combinedAny = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: Self.anyInputEventType
        )
        return IdleSignalVerification(
            selectedIdleSeconds: hidAny,
            hidAnyInputSeconds: hidAny,
            combinedAnyInputSeconds: combinedAny,
            hidNullEventSeconds: CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .null
            ),
            hidKeyDownSeconds: CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .keyDown
            ),
            hidMouseMovedSeconds: CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .mouseMoved
            ),
            hidScrollWheelSeconds: CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .scrollWheel
            ),
            hidAndCombinedAgree: abs(hidAny - combinedAny) < 0.25
        )
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: NSNotification.Name,
        action: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        observers.append(token)
    }

    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: anyInputEventType
        )
    }

    private static func displaySleepState() -> TriState {
        DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: onlineDisplaySleepStates())
    }

    private static func onlineDisplaySleepStates() -> [Bool]? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        var writtenCount = displayCount
        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &writtenCount) == .success,
              writtenCount > 0 else {
            return nil
        }

        return displayIDs.prefix(Int(writtenCount)).map { displayID in
            CGDisplayIsAsleep(displayID) != 0
        }
    }

    private static func displaySnapshots() -> [DisplaySnapshot] {
        NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
            let quartzFrame = CGDisplayBounds(id)
            let appKitFrame = screen.frame
            let visible = screen.visibleFrame
            let leftInset = visible.minX - appKitFrame.minX
            let rightInset = appKitFrame.maxX - visible.maxX
            let bottomInset = visible.minY - appKitFrame.minY
            let topInset = appKitFrame.maxY - visible.maxY
            let quartzVisibleFrame = CGRect(
                x: quartzFrame.minX + leftInset,
                y: quartzFrame.minY + topInset,
                width: quartzFrame.width - leftInset - rightInset,
                height: quartzFrame.height - topInset - bottomInset
            )
            return DisplaySnapshot(
                id: id,
                frame: RectSnapshot(quartzFrame),
                visibleFrame: RectSnapshot(quartzVisibleFrame),
                isMain: screen == NSScreen.main
            )
        }
    }

    private static func frontmostWindowFrameFromWindowServer() -> RectSnapshot? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[CFString: Any]] else {
            return nil
        }

        for window in windowInfo {
            guard let ownerPID = window[kCGWindowOwnerPID] as? Int,
                  ownerPID == Int(frontmostPID),
                  let layer = window[kCGWindowLayer] as? Int,
                  layer == 0,
                  let boundsValue = window[kCGWindowBounds],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
                  bounds.width > 100,
                  bounds.height > 100 else {
                continue
            }
            return RectSnapshot(bounds)
        }
        return nil
    }

    private static func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success,
        let value else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func focusedWindowFrame() -> RectSnapshot? {
        guard let window = focusedWindowElement() else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return RectSnapshot(
            x: Double(position.x),
            y: Double(position.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private static func fullScreenState(
        window: AXUIElement,
        frame: RectSnapshot?,
        display: DisplaySnapshot?
    ) -> TriState {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
           let bool = value as? Bool {
            return bool ? .yes : .no
        }
        guard let frame, let display else { return .unknown }
        return GeometryPolicy.isFullScreen(window: frame, display: display.frame) ? .yes : .no
    }
}

private extension RectSnapshot {
    init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }
}
