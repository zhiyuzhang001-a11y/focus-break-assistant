import Foundation

public struct DisplayAccessibilityOptions: Equatable, Sendable {
    public let reduceMotion: Bool
    public let increaseContrast: Bool
    public let reduceTransparency: Bool

    public init(
        reduceMotion: Bool,
        increaseContrast: Bool,
        reduceTransparency: Bool
    ) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
    }
}

public enum OverlayAccessibilityPolicy {
    public static func animationDuration(
        requested: TimeInterval,
        options: DisplayAccessibilityOptions
    ) -> TimeInterval {
        options.reduceMotion ? min(requested, 0.15) : requested
    }

    public static func surfaceAlpha(
        defaultAlpha: Double,
        options: DisplayAccessibilityOptions
    ) -> Double {
        options.increaseContrast || options.reduceTransparency ? 1 : defaultAlpha
    }

    public static func lineWidth(options: DisplayAccessibilityOptions) -> Double {
        options.increaseContrast ? 1.5 : 1
    }

    public static func showsOutline(options: DisplayAccessibilityOptions) -> Bool {
        options.increaseContrast
    }
}
