import Foundation
import Testing
@testable import FocusBreakProbeCore

struct ImagePreferencesTests {
    @Test func dailyPromptAndSelectionSurviveRestart() throws {
        let suite = "ImagePreferencesTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ImagePreferences(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let day = Date(timeIntervalSince1970: 1_783_440_000)
        #expect(preferences.categories == [.nature])
        #expect(!preferences.shouldAsk(at: day, calendar: calendar))
        preferences.askDaily = true
        #expect(preferences.shouldAsk(at: day, calendar: calendar))
        preferences.markPresented(at: day)
        preferences.categories = [.people, .cartoon, .people]
        preferences.peopleStyle = "运动"
        preferences.active = true
        let restored = ImagePreferences(defaults: defaults)
        #expect(!restored.shouldAsk(at: day.addingTimeInterval(60), calendar: calendar))
        #expect(restored.shouldAsk(at: day.addingTimeInterval(86400), calendar: calendar))
        #expect(restored.categories == [.people, .cartoon])
        #expect(restored.peopleStyle == "运动")
        #expect(restored.active)
        restored.askDaily = false
        #expect(!restored.shouldAsk(at: day.addingTimeInterval(86400), calendar: calendar))
        restored.categories = []
        #expect(restored.categories == [.nature])
        #expect(ImageCategory.space.onlineQuery == nil)
        #expect(ImageCategory.cartoon.onlineQuery == nil)
    }
}
