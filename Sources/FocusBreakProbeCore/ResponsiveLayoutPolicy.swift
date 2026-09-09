import Foundation

public enum ResponsiveLayoutPolicy {
    public static func frame(in visible: RectSnapshot) -> RectSnapshot {
        let width = visible.width * 0.90
        let height = visible.height * 0.65
        return RectSnapshot(x: visible.x + (visible.width - width) / 2,
                            y: visible.y + visible.height - height,
                            width: width, height: height)
    }

    /// Fit the photo itself inside the screen limits, rather than a fixed-aspect card.
    public static func imageFrame(in visible: RectSnapshot, sourceWidth: Double, sourceHeight: Double) -> RectSnapshot {
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else {
            return frame(in: visible)
        }
        let scale = min(visible.width * 0.90 / sourceWidth, visible.height * 0.85 / sourceHeight)
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return RectSnapshot(x: visible.x + (visible.width - width) / 2,
                            y: visible.y + visible.height - height,
                            width: width, height: height)
    }

    public static func fontSize(base: Double, width: Double, height: Double) -> Double {
        let scale = min(width / 1296, height / 552.5)
        return min(48, max(28, base * sqrt(max(0, scale))))
    }

    /// Automatic fill when at least 80% of the original survives, otherwise contain.
    public static func photoDestination(sourceWidth: Double, sourceHeight: Double,
                                         targetWidth: Double, targetHeight: Double) -> RectSnapshot {
        guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
            return RectSnapshot(x: 0, y: 0, width: 0, height: 0)
        }
        let ratio = (sourceWidth / sourceHeight) / (targetWidth / targetHeight)
        if min(ratio, 1 / ratio) >= 0.8 {
            return RectSnapshot(x: 0, y: 0, width: targetWidth, height: targetHeight)
        }
        let scale = min(targetWidth / sourceWidth, targetHeight / sourceHeight)
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return RectSnapshot(x: (targetWidth - width) / 2, y: (targetHeight - height) / 2,
                            width: width, height: height)
    }

    /// Source pixels, measured from the top left. Focal coordinates are normalized 0...1.
    public static func crop(sourceWidth: Double, sourceHeight: Double,
                            targetWidth: Double, targetHeight: Double,
                            focalX: Double, focalY: Double) -> RectSnapshot {
        guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
            return RectSnapshot(x: 0, y: 0, width: max(0, sourceWidth), height: max(0, sourceHeight))
        }
        let scale = max(targetWidth / sourceWidth, targetHeight / sourceHeight)
        let width = min(sourceWidth, targetWidth / scale)
        let height = min(sourceHeight, targetHeight / scale)
        let x = min(max(0, min(1, max(0, focalX)) * sourceWidth - width / 2), sourceWidth - width)
        let y = min(max(0, min(1, max(0, focalY)) * sourceHeight - height / 2), sourceHeight - height)
        return RectSnapshot(x: x, y: y, width: width, height: height)
    }
}
