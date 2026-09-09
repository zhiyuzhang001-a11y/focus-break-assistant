import AppKit
import FocusBreakProbeCore

/// Two explicitly separate lanes: actual system activity and a 45-minute wall-clock
/// engine run with injected active input. Neither lane synthesizes OS input or prevents sleep.
@MainActor
final class OvernightVerification {
    private let output: URL
    private let deadline: Date
    private let suite = "FocusBreakOvernight." + UUID().uuidString
    private var actual: ReminderCoordinator?
    private var collector: MacSignalCollector?
    private var timer: Timer?
    private var injected = ReminderEngine()
    private var injectedCount = 0
    private var actualCount = 0
    private var samples = 0
    private var lastDay = Calendar.current.startOfDay(for: Date())
    private var lastDisplays: [String] = []
    private var overlay: HorizonOverlay?
    private var started = Date()
    private var lastStatus = ""
    init(output: URL, seconds: TimeInterval = 12 * 3600) {
        self.output = output
        deadline = Date(timeIntervalSinceNow: min(24 * 3600, max(60, seconds)))
    }
    private func log(_ event: String, _ values: [String: Any] = [:]) {
        var row = values
        row["event"] = event; row["at"] = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10])
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch { FileHandle.standardError.write(Data("overnight log failed: \(error)\n".utf8)) }
    }
    func start() throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        log("started", ["pid": ProcessInfo.processInfo.processIdentifier,
            "deadline": ISO8601DateFormatter().string(from: deadline),
            "actualLane": "real activity, real 45-minute interval; idle may prevent a reminder",
            "injectedLane": "real wall clock, injected active samples; NOT real continuous human use"])
        collector = MacSignalCollector { [weak self] event in self?.log("system-event", ["name": event]) }
        let coordinator = ReminderCoordinator(defaults: UserDefaults(suiteName: suite)!)
        actual = coordinator
        coordinator.onStatus = { [weak self] status in
            guard let self, self.lastStatus != status else { return }
            self.lastStatus = status; self.log("actual-status", ["status": status])
        }
        coordinator.onSystemRest = { [weak self] in self?.overlay?.dismiss(); self?.overlay = nil }
        coordinator.onReminder = { [weak self] in
            guard let self, let screen = NSScreen.main else { return false }
            let overlay = HorizonOverlay(screen: screen)
            self.overlay = overlay
            overlay.show(fadeIn: 0.3, hold: 15, terminateApplicationOnCompletion: false) { [weak self] in self?.overlay = nil }
            self.actualCount += 1
            self.log("actual-reminder", ["count": self.actualCount, "elapsedWallSeconds": Date().timeIntervalSince(self.started)])
            return true
        }
        coordinator.start()
        tick()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func tick() {
        samples += 1
        if injected.update(now: ProcessInfo.processInfo.systemUptime, idle: 0, unavailable: false, fullScreen: .no) {
            injected.didPresent(); injectedCount += 1
            log("injected-45-minute-threshold", ["count": injectedCount, "elapsedWallSeconds": Date().timeIntervalSince(started),
                "injectedActivity": true, "actualUserAcceptance": false])
        }
        let day = Calendar.current.startOfDay(for: Date())
        if day != lastDay { log("local-day-changed"); lastDay = day }
        let displays = NSScreen.screens.map { "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"):\($0.frame)" }
        if displays != lastDisplays { log("display-topology", ["displays": displays]); lastDisplays = displays }
        if samples % 12 == 1, let activity = collector?.activitySnapshot() {
            log("minute-sample", ["idleSeconds": activity.idleSeconds, "sessionInactive": activity.sessionInactive,
                "systemSleeping": activity.systemSleeping, "actualAccumulated": actual?.engine.accumulated ?? 0,
                "injectedAccumulated": injected.accumulated, "windowCount": NSApp.windows.count,
                "actualReminders": actualCount, "injectedReminders": injectedCount])
        }
        if Date() >= deadline {
            log("finished", ["samples": samples, "actualReminders": actualCount, "injectedReminders": injectedCount,
                "elapsedWallSeconds": Date().timeIntervalSince(started)])
            timer?.invalidate(); overlay?.dismiss()
            UserDefaults.standard.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }
}
