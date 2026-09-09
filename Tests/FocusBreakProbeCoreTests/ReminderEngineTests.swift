import Testing
@testable import FocusBreakProbeCore

@Suite("Reminder timing and transitions")
struct ReminderEngineTests {
    @Test("45 minutes of use yields exactly one reminder per cycle")
    func thresholdAndOnePerCycle() {
        var engine = ReminderEngine()
        for second in stride(from: 0, to: 2700, by: 5) {
            let show9 = engine.update(now: Double(second), idle: 0, unavailable: false, fullScreen: .no)
            #expect(!show9)
        }
        let show11 = engine.update(now: 2700, idle: 0, unavailable: false, fullScreen: .no)
        #expect(show11)
        engine.didPresent()
        for second in stride(from: 2705, through: 5400, by: 5) {
            let show14 = engine.update(now: Double(second), idle: 0, unavailable: false, fullScreen: .no)
            #expect(!show14)
        }
        #expect(engine.hasReminded)
        _ = engine.update(now: 5405, idle: 300, unavailable: false, fullScreen: .no)
        #expect(!engine.hasReminded && engine.accumulated == 0)
    }

    @Test("Short absence pauses at three minutes and natural rest cancels pending work")
    func idle() {
        var engine = ReminderEngine(interval: 10)
        _ = engine.update(now: 0, idle: 175, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 5, idle: 180, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 10, idle: 185, unavailable: false, fullScreen: .no)
        #expect(engine.accumulated == 0)
        _ = engine.update(now: 15, idle: 0, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 20, idle: 0, unavailable: false, fullScreen: .yes)
        _ = engine.update(now: 25, idle: 0, unavailable: false, fullScreen: .yes)
        #expect(engine.isDue)
        _ = engine.update(now: 30, idle: 300, unavailable: false, fullScreen: .no)
        #expect(!engine.isDue && engine.accumulated == 0)
        let show34 = engine.update(now: 35, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show34)
    }

    @Test("Fullscreen, unknown context and settings postpone; acknowledge only actual display")
    func deferral() {
        var engine = ReminderEngine(interval: 10)
        _ = engine.update(now: 0, idle: 0, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 5, idle: 0, unavailable: false, fullScreen: .no)
        let show42 = engine.update(now: 10, idle: 0, unavailable: false, fullScreen: .yes)
        #expect(!show42)
        #expect(engine.isDue)
        let show44 = engine.update(now: 15, idle: 0, unavailable: false, fullScreen: .unknown)
        #expect(!show44)
        let show45 = engine.update(now: 20, idle: 0, unavailable: false, fullScreen: .no, uiBusy: true)
        #expect(!show45)
        let show46 = engine.update(now: 25, idle: 0, unavailable: false, fullScreen: .no)
        #expect(show46)
        let show47 = engine.update(now: 25, idle: 0, unavailable: false, fullScreen: .no)
        #expect(show47)
        engine.didPresent()
        let show49 = engine.update(now: 30, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show49)
    }

    @Test("Sleep, inactive session and a long callback gap cannot catch up or deliver stale reminders")
    func suspension() {
        for gap in [false, true] {
            var engine = ReminderEngine(interval: 10)
            _ = engine.update(now: 0, idle: 0, unavailable: false, fullScreen: .yes)
            _ = engine.update(now: 10, idle: 0, unavailable: false, fullScreen: .yes)
            #expect(engine.isDue)
            let show59 = engine.update(now: gap ? 500 : 15, idle: 0, unavailable: !gap, fullScreen: .no)
            #expect(!show59)
            #expect(engine.accumulated == 0 && !engine.isDue)
            let show61 = engine.update(now: gap ? 505 : 20, idle: 0, unavailable: false, fullScreen: .no)
            #expect(!show61)
        }
    }

    @Test("Pause time is excluded; interval changes restart and app restarts discard old cycles")
    func settings() {
        var engine = ReminderEngine(interval: 20)
        _ = engine.update(now: 0, idle: 0, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 5, idle: 0, unavailable: false, fullScreen: .no)
        engine.setPaused(true)
        let show71 = engine.update(now: 1000, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show71)
        engine.setPaused(false)
        _ = engine.update(now: 1005, idle: 0, unavailable: false, fullScreen: .no)
        #expect(engine.accumulated == 5)
        engine.setInterval(60)
        #expect(engine.accumulated == 0 && engine.interval == 60)
        engine = ReminderEngine()
        #expect(engine.accumulated == 0 && !engine.hasReminded)
    }

    @Test("Invalid samples never trigger reminders")
    func invalidSamples() {
        var engine = ReminderEngine(interval: 1)
        let show84 = engine.update(now: .nan, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show84)
        let show85 = engine.update(now: 0, idle: -1, unavailable: false, fullScreen: .no)
        #expect(!show85)
        let show86 = engine.update(now: 10, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show86)
        let show87 = engine.update(now: 1, idle: 0, unavailable: false, fullScreen: .no)
        #expect(!show87)
    }
    @Test("Snooze retries after five active minutes, excludes pause, and preserves configured interval")
    func snoozeRetry() {
        var engine = ReminderEngine(interval: 10)
        _ = engine.update(now: 0, idle: 0, unavailable: false, fullScreen: .no)
        _ = engine.update(now: 10, idle: 0, unavailable: false, fullScreen: .no)
        engine.didPresent()
        engine.snooze()
        #expect(engine.remaining == 300 && !engine.hasReminded && engine.interval == 10)
        _ = engine.update(now: 15, idle: 0, unavailable: false, fullScreen: .no)
        for second in stride(from: 20, through: 310, by: 5) {
            let showRetry1 = engine.update(now: Double(second), idle: 0, unavailable: false, fullScreen: .no)
            #expect(!showRetry1)
        }
        engine.setPaused(true)
        _ = engine.update(now: 1000, idle: 0, unavailable: false, fullScreen: .no)
        engine.setPaused(false)
        _ = engine.update(now: 1005, idle: 0, unavailable: false, fullScreen: .no)
        #expect(engine.remaining == 5)
        let showRetry2 = engine.update(now: 1010, idle: 0, unavailable: false, fullScreen: .yes)
        #expect(!showRetry2)
        #expect(engine.isDue)
        let showRetry3 = engine.update(now: 1015, idle: 0, unavailable: false, fullScreen: .no)
        #expect(showRetry3)
        engine.didPresent()
        #expect(!engine.isDue)
    }

    @Test("Skip restarts the full interval; natural rest and interval changes cancel snooze")
    func skipAndCancelRetry() {
        var engine = ReminderEngine(interval: 60)
        engine.snooze()
        engine.skip()
        #expect(engine.remaining == 60 && !engine.hasReminded)
        _ = engine.update(now: 0, idle: 0, unavailable: false, fullScreen: .no)
        for second in stride(from: 5, to: 60, by: 5) {
            let showRetry4 = engine.update(now: Double(second), idle: 0, unavailable: false, fullScreen: .no)
            #expect(!showRetry4)
        }
        let showRetry5 = engine.update(now: 60, idle: 0, unavailable: false, fullScreen: .no)
        #expect(showRetry5)
        engine.snooze()
        _ = engine.update(now: 65, idle: 300, unavailable: false, fullScreen: .no)
        #expect(engine.remaining == 60)
        engine.snooze()
        engine.setInterval(90)
        #expect(engine.remaining == 90)
    }

    @Test("Explicit break runs five minutes without charging work time, then starts a new cycle")
    func explicitBreak() {
        var engine = ReminderEngine(interval: 60)
        engine.beginBreak(now: 100)
        for time in stride(from: 100, to: 400, by: 5) {
            let show = engine.update(now: Double(time), idle: 0, unavailable: false, fullScreen: .no)
            #expect(!show && engine.accumulated == 0 && engine.breakEndsAt == 400)
        }
        _ = engine.update(now: 400, idle: 0, unavailable: false, fullScreen: .no)
        #expect(engine.breakEndsAt == nil && engine.remaining == 60)
        engine.beginBreak(now: 500)
        _ = engine.update(now: 505, idle: 0, unavailable: true, fullScreen: .no)
        #expect(engine.breakEndsAt == nil && engine.remaining == 60)
    }

    @Test("Unanswered reminders restart normally or retry only once; rest cancels retry")
    func unansweredPolicy() {
        func present(_ engine: inout ReminderEngine, from start: Double) {
            _ = engine.update(now: start, idle: 0, unavailable: false, fullScreen: .no)
            let duration = engine.remaining
            for offset in stride(from: 5.0, through: duration, by: 5) {
                _ = engine.update(now: start + offset, idle: 0, unavailable: false, fullScreen: .no)
            }
            #expect(engine.isDue)
            engine.didPresent()
        }
        var engine = ReminderEngine(interval: 2700)
        present(&engine, from: 0)
        engine.finishReminder(expired: true, retryUnanswered: false)
        #expect(engine.remaining == 2700 && !engine.hasReminded)
        present(&engine, from: 3000)
        engine.finishReminder(expired: true, retryUnanswered: true)
        #expect(engine.remaining == 300)
        // Dismissal callback after expiration must not cancel the retry.
        engine.finishReminder(expired: false, retryUnanswered: true)
        #expect(engine.remaining == 300)
        present(&engine, from: 6000)
        engine.finishReminder(expired: true, retryUnanswered: true)
        #expect(engine.remaining == 2700)
        present(&engine, from: 6400)
        engine.finishReminder(expired: false, retryUnanswered: true)
        #expect(engine.remaining == 2700)
        present(&engine, from: 9200)
        engine.finishReminder(expired: true, retryUnanswered: true)
        _ = engine.update(now: 11905, idle: 300, unavailable: false, fullScreen: .no)
        #expect(engine.remaining == 2700)
        for time in stride(from: 12000.0, through: 15600, by: 5) {
            let show = engine.update(now: time, idle: 600, unavailable: false, fullScreen: .no)
            #expect(!show && engine.accumulated == 0)
        }
        _ = engine.update(now: 15605, idle: 0, unavailable: false, fullScreen: .no)
        #expect(engine.remaining == 2700)
    }

}
