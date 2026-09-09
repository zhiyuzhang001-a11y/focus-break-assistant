import AppKit

/// A flipped document starts at the top of a scroll view even when content is short.
@MainActor
final class SettingsStackView: NSStackView {
    override var isFlipped: Bool { true }
}
