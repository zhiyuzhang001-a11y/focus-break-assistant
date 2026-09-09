import Foundation
import Testing
@testable import FocusBreakProbeCore

struct PresentationAndVarietyTests {
    @Test func varietyDefersSimilarPhotosWithoutLosingTheRound() {
        let ids = ["one", "two", "three", "four"]
        var rotation = PhotoRotation()
        let first = rotation.next(in: ids, avoiding: ["one", "two", "three"])
        #expect(first == "four")
        rotation.didShow("four")
        var shown = [first!]
        for _ in 0..<3 {
            let next = rotation.next(in: ids, avoiding: Set(ids))!
            shown.append(next); rotation.didShow(next)
        }
        #expect(Set(shown) == Set(ids))
        let next = rotation.next(in: ids, avoiding: Set(ids))
        #expect(next != shown.last)
    }
    @Test func textChoicesPersistIndependentlyOfDailyCategoryChanges() throws {
        let suite = "Presentation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ReminderPresentation(defaults: defaults)
        #expect(settings.position == .center && !settings.brief)
        settings.position = .bottom; settings.brief = true
        ImagePreferences(defaults: defaults).categories = [.people]
        let restored = ReminderPresentation(defaults: defaults)
        #expect(restored.position == .bottom && restored.brief)
        #expect(!restored.message.contains("\n"))
    }
}
