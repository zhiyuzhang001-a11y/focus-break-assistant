import AppKit

/// Uses real activity/full-screen signals and a short interval in an isolated settings suite.
@MainActor
final class AutomaticReminderVerification {
    private let suite = "FocusBreakReminderTest." + UUID().uuidString
    private var coordinator: ReminderCoordinator?
    private var overlay: HorizonOverlay?
    private var count = 0
    private let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

    func start() {
        let defaults = UserDefaults(suiteName: suite)!
        let coordinator = ReminderCoordinator(defaults: defaults, intervalOverride: 2)
        self.coordinator = coordinator
        coordinator.onReminder = { [weak self] in
            guard let self, let screen = NSScreen.main else { return false }
            let overlay = HorizonOverlay(screen: screen)
            self.overlay = overlay
            self.count += 1
            overlay.show(fadeIn: 0.3, hold: 0.5, fadeOut: 0.2, terminateApplicationOnCompletion: false)
            return true
        }
        coordinator.start()
        Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let result = [
                    "automaticOverlayDeliveredOnce": self.count == 1,
                    "cycleAcknowledged": self.coordinator?.engine.hasReminded == true,
                    "frontmostApplicationUnchanged": self.frontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier
                ]
                let data = try! JSONEncoder().encode(result)
                FileHandle.standardOutput.write(data)
                UserDefaults.standard.removePersistentDomain(forName: self.suite)
                exit(result.values.allSatisfy { $0 } ? 0 : 1)
            }
        }
    }
}
