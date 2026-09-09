import Testing
@testable import FocusBreakProbeCore

@Suite("Responsive photo layout")
struct ResponsiveLayoutPolicyTests {
    @Test("Fits small, portrait, wide and offset screens without losing half-screen coverage")
    func screenCoverage() {
        for (width, height) in [(640.0, 430.0), (900, 1550), (2560, 1030), (2560, 1390)] {
            let visible = RectSnapshot(x: -2560, y: -180, width: width, height: height)
            let frame = ResponsiveLayoutPolicy.frame(in: visible)
            #expect(frame.width * frame.height >= width * height / 2)
            #expect(abs(frame.x + frame.width / 2 - (visible.x + width / 2)) < 0.001)
            #expect(abs(frame.y + frame.height - (visible.y + height)) < 0.001)
            #expect(frame.y >= visible.y && frame.x >= visible.x)
            let font = ResponsiveLayoutPolicy.fontSize(base: 36, width: frame.width, height: frame.height)
            #expect((28...48).contains(font))
            #expect(font * 12 <= frame.width - 48)
        }
    }

    @Test("Crop preserves aspect, stays inside source and retains a focal point near every edge")
    func focalCropping() {
        for (tw, th) in [(2304.0, 670.0), (810, 1007), (576, 279)] {
            for (fx, fy) in [(0.05, 0.05), (0.95, 0.95), (0.5, 0.52)] {
                let r = ResponsiveLayoutPolicy.crop(sourceWidth: 2400, sourceHeight: 3600,
                    targetWidth: tw, targetHeight: th, focalX: fx, focalY: fy)
                #expect(abs(r.width / r.height - tw / th) < 0.0001)
                #expect(r.x >= 0 && r.y >= 0 && r.x + r.width <= 2400.001 && r.y + r.height <= 3600.001)
                #expect(r.x <= fx * 2400 && r.x + r.width >= fx * 2400)
                #expect(r.y <= fy * 3600 && r.y + r.height >= fy * 3600)
            }
        }
        let wide = ResponsiveLayoutPolicy.crop(sourceWidth: 3600, sourceHeight: 2400,
            targetWidth: 800, targetHeight: 1400, focalX: 0.9, focalY: 0.3)
        #expect(wide.x > 2000)
        #expect(abs(wide.width / wide.height - 800.0 / 1400) < 0.0001)
    }
}

@Suite("Photo-shaped reminder window")
struct ImageFrameTests {
    @Test func fitsCompletePhotoWithoutLetterboxOrCrop() {
        for (sw, sh) in [(640.0, 430.0), (1440, 900), (900, 1550), (3440, 1440)] {
            let screen = RectSnapshot(x: -1500, y: 120, width: sw, height: sh)
            for (iw, ih) in [(1600.0, 900.0), (3000, 2000), (2000, 3000), (1000, 1000), (4000, 1000)] {
                let frame = ResponsiveLayoutPolicy.imageFrame(in: screen, sourceWidth: iw, sourceHeight: ih)
                #expect(abs(frame.width / frame.height - iw / ih) < 0.00001)
                #expect(frame.width <= sw * 0.9 + 0.001 && frame.height <= sh * 0.85 + 0.001)
                #expect(abs(frame.x + frame.width / 2 - (screen.x + sw / 2)) < 0.001)
                #expect(abs(frame.y + frame.height - (screen.y + sh)) < 0.001)
                let destination = ResponsiveLayoutPolicy.photoDestination(sourceWidth: iw, sourceHeight: ih, targetWidth: frame.width, targetHeight: frame.height)
                #expect(destination.x == 0 && destination.y == 0)
                #expect(destination.width == frame.width && destination.height == frame.height)
                let crop = ResponsiveLayoutPolicy.crop(sourceWidth: iw, sourceHeight: ih, targetWidth: frame.width, targetHeight: frame.height, focalX: 0.95, focalY: 0.05)
                #expect(abs(crop.width - iw) < 0.001 && abs(crop.height - ih) < 0.001)
            }
        }
    }
    @Test func invalidImageUsesSafeFallback() {
        let screen = RectSnapshot(x: 0, y: 0, width: 1440, height: 900)
        let frame = ResponsiveLayoutPolicy.imageFrame(in: screen, sourceWidth: .nan, sourceHeight: 100)
        #expect(frame.width.isFinite && frame.height.isFinite)
    }
}
