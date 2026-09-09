import Foundation

/// Active-use timing; natural rest cancels pending reminders and retries.
public struct ReminderEngine {
    public private(set) var accumulated: TimeInterval = 0
    public private(set) var hasReminded = false
    public private(set) var interval: TimeInterval
    public private(set) var isPaused = false
    public private(set) var breakEndsAt: TimeInterval?
    private var automaticRetryUsed = false
    private var retryInterval: TimeInterval?
    public var remaining: TimeInterval { max(0, (retryInterval ?? interval) - accumulated) }
    private var previousTime: TimeInterval?
    private var previousIdle: TimeInterval = 0

    public init(interval: TimeInterval = 45 * 60) { self.interval = max(1, interval) }
    public var isDue: Bool { breakEndsAt == nil && remaining == 0 && !hasReminded && !isPaused }

    public mutating func reset() {
        breakEndsAt = nil
        automaticRetryUsed = false
        retryInterval = nil
        accumulated = 0
        hasReminded = false
        previousTime = nil
        previousIdle = 0
    }

    public mutating func setPaused(_ value: Bool) {
        isPaused = value
        previousTime = nil // Never charge time spent paused.
    }

    public mutating func setInterval(_ value: TimeInterval) {
        interval = max(1, value)
        reset()
    }

    /// Returns permission to present; only acknowledge after a real overlay was created.
    public mutating func update(now: TimeInterval, idle: TimeInterval,
                                unavailable: Bool, fullScreen: TriState, uiBusy: Bool = false) -> Bool {
        guard now.isFinite, idle.isFinite, idle >= 0 else { reset(); return false }
        if let end = breakEndsAt {
            if unavailable || now >= end { reset() }
            else { previousTime = nil; return false }
        }
        guard !unavailable, idle < 300 else { reset(); return false }
        guard !isPaused else { previousTime = nil; return false }
        if let previousTime {
            let delta = now - previousTime
            // A long or backwards gap means suspended execution; never catch up on old time.
            guard delta >= 0, delta <= 30 else {
                reset()
                self.previousTime = now
                previousIdle = idle
                return false
            }
            if idle < 180, previousIdle < 180 {
                accumulated = min(retryInterval ?? interval, accumulated + delta)
            }
        }
        previousTime = now
        previousIdle = idle
        return isDue && idle < 180 && fullScreen == .no && !uiBusy
    }

    public mutating func beginBreak(now: TimeInterval, duration: TimeInterval = 300) {
        guard now.isFinite, duration.isFinite, duration > 0 else { return }
        reset()
        breakEndsAt = now + duration
    }

    public mutating func snooze() {
        reset()
        retryInterval = 5 * 60
    }

    public mutating func skip() { reset() }

    /// Only expiration may schedule one automatic follow-up. Explicit dismissal starts a full interval.
    public mutating func finishReminder(expired: Bool, retryUnanswered: Bool) {
        guard hasReminded else { return } // An explicit action or natural rest already handled it.
        let shouldRetry = expired && retryUnanswered && !automaticRetryUsed
        reset()
        if shouldRetry {
            automaticRetryUsed = true
            retryInterval = 300
        }
    }

    public mutating func didPresent() { if isDue { hasReminded = true } }
}
