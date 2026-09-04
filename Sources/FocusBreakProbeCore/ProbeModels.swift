import Foundation

public struct RectSnapshot: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DisplaySnapshot: Codable, Equatable, Sendable {
    public let id: UInt32
    public let frame: RectSnapshot
    public let visibleFrame: RectSnapshot
    public let isMain: Bool

    public init(id: UInt32, frame: RectSnapshot, visibleFrame: RectSnapshot, isMain: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

public enum TriState: String, Codable, Equatable, Sendable {
    case yes
    case no
    case unknown
}

public struct ActivitySnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let idleSeconds: Double
    public let sessionInactive: Bool
    public let systemSleeping: Bool
    public let displaySleepState: TriState

    public init(
        capturedAt: Date,
        idleSeconds: Double,
        sessionInactive: Bool,
        systemSleeping: Bool,
        displaySleepState: TriState
    ) {
        self.capturedAt = capturedAt
        self.idleSeconds = idleSeconds
        self.sessionInactive = sessionInactive
        self.systemSleeping = systemSleeping
        self.displaySleepState = displaySleepState
    }
}

public struct ProbeSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let idleSeconds: Double
    public let sessionInactive: Bool
    public let systemSleeping: Bool
    public let displaySleepState: TriState
    public let accessibilityTrusted: Bool
    public let activeDisplayID: UInt32?
    public let activeDisplaySource: String
    public let coordinateSpace: String
    public let focusedWindowFullScreen: TriState
    public let displays: [DisplaySnapshot]

    public init(
        capturedAt: Date,
        idleSeconds: Double,
        sessionInactive: Bool,
        systemSleeping: Bool,
        displaySleepState: TriState,
        accessibilityTrusted: Bool,
        activeDisplayID: UInt32?,
        activeDisplaySource: String,
        coordinateSpace: String = "quartz_global_top_left",
        focusedWindowFullScreen: TriState,
        displays: [DisplaySnapshot]
    ) {
        self.capturedAt = capturedAt
        self.idleSeconds = idleSeconds
        self.sessionInactive = sessionInactive
        self.systemSleeping = systemSleeping
        self.displaySleepState = displaySleepState
        self.accessibilityTrusted = accessibilityTrusted
        self.activeDisplayID = activeDisplayID
        self.activeDisplaySource = activeDisplaySource
        self.coordinateSpace = coordinateSpace
        self.focusedWindowFullScreen = focusedWindowFullScreen
        self.displays = displays
    }
}

public struct OverlayVerification: Codable, Sendable {
    public let frontmostPIDBefore: Int32?
    public let frontmostPIDAfter: Int32?
    public let frontmostApplicationUnchanged: Bool
    public let ignoresMouseEvents: Bool
    public let canBecomeKey: Bool
    public let canBecomeMain: Bool
    public let isKeyWindow: Bool
    public let isMainWindow: Bool
    public let windowLevel: Int
    public let reduceMotionEnabled: Bool
    public let increaseContrastEnabled: Bool
    public let reduceTransparencyEnabled: Bool
    public let effectiveAppearance: String
    public let textPointSize: Double

    public init(
        frontmostPIDBefore: Int32?,
        frontmostPIDAfter: Int32?,
        frontmostApplicationUnchanged: Bool,
        ignoresMouseEvents: Bool,
        canBecomeKey: Bool,
        canBecomeMain: Bool,
        isKeyWindow: Bool,
        isMainWindow: Bool,
        windowLevel: Int,
        reduceMotionEnabled: Bool,
        increaseContrastEnabled: Bool,
        reduceTransparencyEnabled: Bool,
        effectiveAppearance: String,
        textPointSize: Double
    ) {
        self.frontmostPIDBefore = frontmostPIDBefore
        self.frontmostPIDAfter = frontmostPIDAfter
        self.frontmostApplicationUnchanged = frontmostApplicationUnchanged
        self.ignoresMouseEvents = ignoresMouseEvents
        self.canBecomeKey = canBecomeKey
        self.canBecomeMain = canBecomeMain
        self.isKeyWindow = isKeyWindow
        self.isMainWindow = isMainWindow
        self.windowLevel = windowLevel
        self.reduceMotionEnabled = reduceMotionEnabled
        self.increaseContrastEnabled = increaseContrastEnabled
        self.reduceTransparencyEnabled = reduceTransparencyEnabled
        self.effectiveAppearance = effectiveAppearance
        self.textPointSize = textPointSize
    }
}

public struct PreviewMenuVerification: Codable, Sendable {
    public let hasStatusItemButton: Bool
    public let hasTemplateIcon: Bool
    public let menuItemTitles: [String]
    public let overlay: OverlayVerification

    public init(
        hasStatusItemButton: Bool,
        hasTemplateIcon: Bool,
        menuItemTitles: [String],
        overlay: OverlayVerification
    ) {
        self.hasStatusItemButton = hasStatusItemButton
        self.hasTemplateIcon = hasTemplateIcon
        self.menuItemTitles = menuItemTitles
        self.overlay = overlay
    }
}

public struct SyntheticTransitionVerification: Codable, Sendable {
    public let observedEvents: [String]
    public let sessionTransitionPassed: Bool
    public let systemSleepTransitionPassed: Bool
    public let displayNotificationHintsObserved: Bool
    public let finalStateRestored: Bool

    public init(
        observedEvents: [String],
        sessionTransitionPassed: Bool,
        systemSleepTransitionPassed: Bool,
        displayNotificationHintsObserved: Bool,
        finalStateRestored: Bool
    ) {
        self.observedEvents = observedEvents
        self.sessionTransitionPassed = sessionTransitionPassed
        self.systemSleepTransitionPassed = systemSleepTransitionPassed
        self.displayNotificationHintsObserved = displayNotificationHintsObserved
        self.finalStateRestored = finalStateRestored
    }
}

public struct IdleSignalVerification: Codable, Sendable {
    public let selectedIdleSeconds: Double
    public let hidAnyInputSeconds: Double
    public let combinedAnyInputSeconds: Double
    public let hidNullEventSeconds: Double
    public let hidKeyDownSeconds: Double
    public let hidMouseMovedSeconds: Double
    public let hidScrollWheelSeconds: Double
    public let hidAndCombinedAgree: Bool

    public init(
        selectedIdleSeconds: Double,
        hidAnyInputSeconds: Double,
        combinedAnyInputSeconds: Double,
        hidNullEventSeconds: Double,
        hidKeyDownSeconds: Double,
        hidMouseMovedSeconds: Double,
        hidScrollWheelSeconds: Double,
        hidAndCombinedAgree: Bool
    ) {
        self.selectedIdleSeconds = selectedIdleSeconds
        self.hidAnyInputSeconds = hidAnyInputSeconds
        self.combinedAnyInputSeconds = combinedAnyInputSeconds
        self.hidNullEventSeconds = hidNullEventSeconds
        self.hidKeyDownSeconds = hidKeyDownSeconds
        self.hidMouseMovedSeconds = hidMouseMovedSeconds
        self.hidScrollWheelSeconds = hidScrollWheelSeconds
        self.hidAndCombinedAgree = hidAndCombinedAgree
    }
}
