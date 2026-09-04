import Testing
@testable import FocusBreakProbeCore

@Suite("Display sleep policy")
struct DisplaySleepPolicyTests {
    @Test("All online displays must be asleep")
    func allDisplaysAsleep() {
        #expect(DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: [true, true]) == .yes)
        #expect(DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: [true, false]) == .no)
        #expect(DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: [false]) == .no)
    }

    @Test("Missing display state is unknown")
    func missingDisplayState() {
        #expect(DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: []) == .unknown)
        #expect(DisplaySleepPolicy.aggregate(onlineDisplaySleepStates: nil) == .unknown)
    }
}
