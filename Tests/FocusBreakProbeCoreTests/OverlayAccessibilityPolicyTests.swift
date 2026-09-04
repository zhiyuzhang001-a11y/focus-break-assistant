import Testing
@testable import FocusBreakProbeCore

@Suite("Overlay accessibility policy")
struct OverlayAccessibilityPolicyTests {
    private let defaults = DisplayAccessibilityOptions(
        reduceMotion: false,
        increaseContrast: false,
        reduceTransparency: false
    )

    @Test("Default settings preserve the requested visual treatment")
    func defaultsPreserveTreatment() {
        #expect(OverlayAccessibilityPolicy.animationDuration(requested: 0.7, options: defaults) == 0.7)
        #expect(OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.86, options: defaults) == 0.86)
        #expect(OverlayAccessibilityPolicy.lineWidth(options: defaults) == 1)
        #expect(!OverlayAccessibilityPolicy.showsOutline(options: defaults))
    }

    @Test("Reduce motion caps both long and already-short transitions")
    func reduceMotionCapsTransitions() {
        let options = DisplayAccessibilityOptions(
            reduceMotion: true,
            increaseContrast: false,
            reduceTransparency: false
        )
        #expect(OverlayAccessibilityPolicy.animationDuration(requested: 0.7, options: options) == 0.15)
        #expect(OverlayAccessibilityPolicy.animationDuration(requested: 0.05, options: options) == 0.05)
    }

    @Test("Increase contrast makes the surface opaque and strengthens structure")
    func increaseContrastStrengthensTreatment() {
        let options = DisplayAccessibilityOptions(
            reduceMotion: false,
            increaseContrast: true,
            reduceTransparency: false
        )
        #expect(OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.86, options: options) == 1)
        #expect(OverlayAccessibilityPolicy.lineWidth(options: options) == 1.5)
        #expect(OverlayAccessibilityPolicy.showsOutline(options: options))
    }

    @Test("Reduce transparency alone makes the surface opaque without adding an outline")
    func reduceTransparencyOnlyAffectsSurface() {
        let options = DisplayAccessibilityOptions(
            reduceMotion: false,
            increaseContrast: false,
            reduceTransparency: true
        )
        #expect(OverlayAccessibilityPolicy.surfaceAlpha(defaultAlpha: 0.88, options: options) == 1)
        #expect(OverlayAccessibilityPolicy.lineWidth(options: options) == 1)
        #expect(!OverlayAccessibilityPolicy.showsOutline(options: options))
    }
}
