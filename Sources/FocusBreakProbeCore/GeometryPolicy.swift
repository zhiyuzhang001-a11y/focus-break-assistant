import Foundation

public enum GeometryPolicy {
    public static func contains(_ point: (x: Double, y: Double), in rect: RectSnapshot) -> Bool {
        point.x >= rect.x
            && point.x < rect.x + rect.width
            && point.y >= rect.y
            && point.y < rect.y + rect.height
    }

    public static func displayContaining(
        point: (x: Double, y: Double),
        displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        displays.first { contains(point, in: $0.frame) }
    }

    public static func displayWithLargestIntersection(
        window: RectSnapshot,
        displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        let ranked = displays.map { display in
            (display: display, area: intersectionArea(window, display.frame))
        }
        guard let best = ranked.max(by: { $0.area < $1.area }), best.area > 0 else {
            return nil
        }
        return best.display
    }

    public static func isFullScreen(
        window: RectSnapshot,
        display: RectSnapshot,
        tolerance: Double = 2
    ) -> Bool {
        abs(window.x - display.x) <= tolerance
            && abs(window.y - display.y) <= tolerance
            && abs(window.width - display.width) <= tolerance
            && abs(window.height - display.height) <= tolerance
    }

    public static func overlayOrigin(
        size: (width: Double, height: Double),
        visibleFrame: RectSnapshot,
        rightMargin: Double = 26,
        topFraction: Double = 0.20
    ) -> (x: Double, y: Double) {
        let safeTopFraction = min(max(topFraction, 0), 1)
        let centerY = visibleFrame.y + visibleFrame.height * (1 - safeTopFraction)
        let rawX = visibleFrame.x + visibleFrame.width - rightMargin - size.width
        let rawY = centerY - size.height / 2
        let maximumX = max(visibleFrame.x, visibleFrame.x + visibleFrame.width - size.width)
        let maximumY = max(visibleFrame.y, visibleFrame.y + visibleFrame.height - size.height)
        return (
            x: min(max(rawX, visibleFrame.x), maximumX),
            y: min(max(rawY, visibleFrame.y), maximumY)
        )
    }

    private static func intersectionArea(_ lhs: RectSnapshot, _ rhs: RectSnapshot) -> Double {
        let minX = max(lhs.x, rhs.x)
        let minY = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        return max(0, maxX - minX) * max(0, maxY - minY)
    }
}
