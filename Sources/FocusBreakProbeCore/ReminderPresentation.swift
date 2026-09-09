import Foundation

public struct ReminderPresentation {
    public enum TextPosition: String, CaseIterable { case center, bottom }
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var position: TextPosition {
        get { TextPosition(rawValue: defaults.string(forKey: "reminderTextPosition") ?? "center") ?? .center }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "reminderTextPosition") }
    }
    public var brief: Bool {
        get { defaults.bool(forKey: "reminderBriefText") }
        nonmutating set { defaults.set(newValue, forKey: "reminderBriefText") }
    }
    public var message: String { brief ? "歇一会儿，看看远处。" : "给下一段留一点余白。\n让目光去远处停一会儿。" }
}
