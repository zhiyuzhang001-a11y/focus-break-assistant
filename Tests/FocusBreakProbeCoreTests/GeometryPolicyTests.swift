import Testing
@testable import FocusBreakProbeCore

@Suite("Geometry policy")
struct GeometryPolicyTests {
    private let primary = DisplaySnapshot(
        id: 1,
        frame: RectSnapshot(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: RectSnapshot(x: 0, y: 25, width: 1440, height: 850),
        isMain: true
    )
    private let secondary = DisplaySnapshot(
        id: 2,
        frame: RectSnapshot(x: 1440, y: -180, width: 1920, height: 1080),
        visibleFrame: RectSnapshot(x: 1440, y: -180, width: 1920, height: 1055),
        isMain: false
    )

    @Test("Pointer coordinates choose the containing display")
    func pointerDisplaySelection() {
        #expect(GeometryPolicy.displayContaining(point: (2000, 400), displays: [primary, secondary])?.id == 2)
        #expect(GeometryPolicy.displayContaining(point: (200, 400), displays: [primary, secondary])?.id == 1)
    }

    @Test("Negative global coordinates select a display on the left")
    func negativeCoordinateDisplaySelection() {
        let leftDisplay = DisplaySnapshot(
            id: 3,
            frame: RectSnapshot(x: -1920, y: -120, width: 1920, height: 1080),
            visibleFrame: RectSnapshot(x: -1920, y: -90, width: 1920, height: 1050),
            isMain: false
        )
        #expect(GeometryPolicy.displayContaining(point: (-900, 200), displays: [primary, leftDisplay])?.id == 3)
    }

    @Test("Focused window chooses display with largest intersection")
    func focusedWindowDisplaySelection() {
        let window = RectSnapshot(x: 1300, y: 100, width: 900, height: 700)
        #expect(GeometryPolicy.displayWithLargestIntersection(window: window, displays: [primary, secondary])?.id == 2)
    }

    @Test("A stale window outside the current topology does not select an arbitrary display")
    func staleWindowDoesNotSelectDisplay() {
        let staleWindow = RectSnapshot(x: 8000, y: 8000, width: 900, height: 700)
        #expect(GeometryPolicy.displayWithLargestIntersection(window: staleWindow, displays: [primary, secondary]) == nil)
    }

    @Test("Full-screen comparison allows small coordinate noise")
    func fullScreenTolerance() {
        let almostFull = RectSnapshot(x: 1, y: -1, width: 1439, height: 901)
        #expect(GeometryPolicy.isFullScreen(window: almostFull, display: primary.frame))
        let ordinaryWindow = RectSnapshot(x: 40, y: 40, width: 1200, height: 780)
        #expect(!GeometryPolicy.isFullScreen(window: ordinaryWindow, display: primary.frame))
        #expect(GeometryPolicy.isFullScreen(window: secondary.frame, display: secondary.frame))
    }

    @Test("Overlay is positioned from the visible frame")
    func overlayPlacement() {
        let origin = GeometryPolicy.overlayOrigin(
            size: (252, 76),
            visibleFrame: primary.visibleFrame
        )
        #expect(origin.x == 1162)
        #expect(origin.y == 667)
    }

    @Test("Overlay stays inside a small visible frame")
    func overlayPlacementIsClamped() {
        let smallFrame = RectSnapshot(x: -300, y: 40, width: 260, height: 100)
        let origin = GeometryPolicy.overlayOrigin(
            size: (252, 76),
            visibleFrame: smallFrame,
            rightMargin: 26,
            topFraction: -1
        )
        #expect(origin.x == -300)
        #expect(origin.y == 64)
    }
}
