import AppKit
import FocusBreakProbeCore

enum ReminderVisualState: String, CaseIterable {
    case working
    case upcoming
    case resting
    case resumed
    case paused
}

@MainActor
final class ReminderCoordinator {
    private let defaults: UserDefaults
    private(set) var engine: ReminderEngine
    private var timer: Timer?
    private var lastIdle: Double = 0
    private var unavailable = false
    private var wasResting = false
    private var resumedUntil: TimeInterval?
    private var pendingReason = "等待检查当前屏幕"
    private lazy var collector = MacSignalCollector { [weak self] _ in
        self?.engine.reset()
        self?.onSystemRest?()
        self?.publishStatus()
    }
    var isUIBusy: () -> Bool = { false }
    var onReminder: () -> Bool = { false }
    var onStatus: (String) -> Void = { _ in }
    var onVisualState: (ReminderVisualState) -> Void = { _ in }
    var onSystemRest: (() -> Void)?
    var isPaused: Bool { engine.isPaused }
    var minutes: Int { Int(engine.interval / 60) }

    init(defaults: UserDefaults = .standard, intervalOverride: TimeInterval? = nil) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: "reminderIntervalMinutes")
        engine = ReminderEngine(interval: intervalOverride ?? Double([30, 45, 60, 90].contains(saved) ? saved : 45) * 60)
        engine.setPaused(defaults.bool(forKey: "remindersPaused"))
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func togglePause() {
        engine.setPaused(!engine.isPaused)
        defaults.set(engine.isPaused, forKey: "remindersPaused")
        publishStatus()
    }

    func changeInterval(_ minutes: Int) {
        guard [30, 45, 60, 90].contains(minutes) else { return }
        engine.setInterval(Double(minutes) * 60)
        defaults.set(minutes, forKey: "reminderIntervalMinutes")
        publishStatus()
    }

    func beginBreak() {
        engine.beginBreak(now: ProcessInfo.processInfo.systemUptime)
        wasResting = true
        publishStatus()
    }
    func snooze() { engine.snooze(); publishStatus() }
    func finishReminder(expired: Bool) {
        engine.finishReminder(expired: expired, retryUnanswered: defaults.bool(forKey: "retryUnansweredReminder"))
        publishStatus()
    }
    func skip() { engine.skip(); publishStatus() }

    private func tick() {
        let activity = collector.activitySnapshot()
        lastIdle = activity.idleSeconds
        unavailable = activity.sessionInactive || activity.systemSleeping || activity.displaySleepState == .yes
        let now = ProcessInfo.processInfo.systemUptime
        _ = engine.update(now: now, idle: lastIdle, unavailable: unavailable, fullScreen: .unknown)
        let isResting = unavailable || lastIdle >= 180 || engine.breakEndsAt != nil
        if wasResting && !isResting { resumedUntil = now + 60 }
        wasResting = isResting
        pendingReason = isUIBusy() ? "设置或提醒窗口正在显示" : "等待恢复使用"
        if engine.isDue, !unavailable, lastIdle < 180, !isUIBusy() {
            let context = collector.snapshot()
            pendingReason = context.displaySleepState != .no ? "无法确认屏幕状态" :
                context.focusedWindowFullScreen == .yes ? "当前应用处于全屏" :
                context.focusedWindowFullScreen == .unknown ? "无法确认全屏状态" : "等待图片显示"
            if engine.update(now: now, idle: context.idleSeconds,
                unavailable: context.sessionInactive || context.systemSleeping || context.displaySleepState == .yes,
                fullScreen: context.displaySleepState == .no ? context.focusedWindowFullScreen : .unknown), onReminder() {
                engine.didPresent()
            }
        }
        publishStatus()
    }

    func publishStatus() {
        onVisualState(visualState)
        let remaining = Int(ceil(engine.remaining / 60))
        if let end = engine.breakEndsAt {
            onStatus("休息中 · 还剩 \(max(0, Int(ceil((end - ProcessInfo.processInfo.systemUptime) / 60)))) 分钟" + (engine.isPaused ? " · 自动提醒已暂停" : ""))
        }
        else if engine.isPaused { onStatus("自动提醒已暂停 · 剩余约 \(remaining) 分钟") }
        else if unavailable || lastIdle >= 300 { onStatus("休息中 · 已开始新的计时周期") }
        else if engine.hasReminded { onStatus("提醒正在显示 · 可休息、稍后或跳过") }
        else if lastIdle >= 180 { onStatus("暂离电脑 · 计时暂停 · 剩余约 \(remaining) 分钟") }
        else if engine.isDue { onStatus("提醒已延后 · \(pendingReason)") }
        else {
            onStatus("距下次提醒约 \(Int(ceil(engine.remaining / 60))) 分钟")
        }
    }

    var visualState: ReminderVisualState {
        if engine.isPaused { return .paused }
        if engine.breakEndsAt != nil || unavailable || lastIdle >= 180 { return .resting }
        if let resumedUntil, ProcessInfo.processInfo.systemUptime < resumedUntil { return .resumed }
        if engine.hasReminded || engine.isDue || engine.remaining <= 5 * 60 { return .upcoming }
        return .working
    }
}
