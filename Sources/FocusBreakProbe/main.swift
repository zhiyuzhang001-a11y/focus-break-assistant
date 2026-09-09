import AppKit
import ApplicationServices
import FocusBreakProbeCore

private enum ProbeCommand {
    case verifyOvernight(seconds: TimeInterval)
    case reviewReservoir
    case fillReservoir
    case snapshot
    case snapshotWithoutAccessibility
    case watch(seconds: TimeInterval)
    case watchContext(seconds: TimeInterval)
    case overlay(textVariant: HorizonTextVariant)
    case verifyOverlay(textVariant: HorizonTextVariant)
    case verifyBundledOverlay(textVariant: HorizonTextVariant)
    case renderVisualMatrix(outputDirectory: String)
    case previewMenu
    case verifyCurtain
    case verifyPhotoLibrary
    case verifyAutomaticReminder
    case verifyPreviewMenu
    case verifySyntheticTransitions
    case verifyIdleSignal
    case requestAccessibility
    case help
}

private func parseCommand(_ arguments: [String]) -> ProbeCommand {
    guard let first = arguments.first, !first.hasPrefix("-psn_") else { return .previewMenu }
    switch first {
    case "--verify-overnight": return .verifyOvernight(seconds: arguments.dropFirst().first.flatMap(TimeInterval.init) ?? 43200)
    case "--review-reservoir": return .reviewReservoir
    case "--fill-reservoir": return .fillReservoir
    case "--snapshot":
        return .snapshot
    case "--snapshot-no-accessibility":
        return .snapshotWithoutAccessibility
    case "--watch":
        let seconds = arguments.dropFirst().first.flatMap(TimeInterval.init) ?? 30
        return .watch(seconds: max(1, seconds))
    case "--watch-context":
        let seconds = arguments.dropFirst().first.flatMap(TimeInterval.init) ?? 30
        return .watchContext(seconds: max(1, seconds))
    case "--overlay", "--preview-reminder":
        return .overlay(textVariant: HorizonTextVariant(rawValue: arguments.dropFirst().first ?? "") ?? .prominent)
    case "--verify-overlay":
        return .verifyOverlay(textVariant: HorizonTextVariant(rawValue: arguments.dropFirst().first ?? "") ?? .prominent)
    case "--verify-bundled-overlay":
        return .verifyBundledOverlay(textVariant: HorizonTextVariant(rawValue: arguments.dropFirst().first ?? "") ?? .prominent)
    case "--render-visual-matrix":
        return .renderVisualMatrix(outputDirectory: arguments.dropFirst().first ?? "artifacts/stage1-visual-matrix")
    case "--verify-automatic-reminder":
        return .verifyAutomaticReminder
    case "--verify-photo-library":
        return .verifyPhotoLibrary
    case "--verify-curtain":
        return .verifyCurtain
    case "--preview-menu":
        return .previewMenu
    case "--verify-preview-menu":
        return .verifyPreviewMenu
    case "--verify-synthetic-transitions", "--verify-lifecycle":
        return .verifySyntheticTransitions
    case "--verify-idle-signal":
        return .verifyIdleSignal
    case "--request-accessibility":
        return .requestAccessibility
    case "--help", "-h":
        return .help
    default:
        return .help
    }
}

private let outputPath: String? = {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}()

@MainActor
private func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        if let outputPath {
            var fileData = data
            fileData.append(Data("\n".utf8))
            try fileData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    } catch {
        FileHandle.standardError.write(Data("encoding error: \(error)\n".utf8))
    }
}

@MainActor
private func run() {
    switch parseCommand(Array(CommandLine.arguments.dropFirst())) {
    case let .verifyOvernight(seconds):
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: outputPath ?? "artifacts/overnight-verification.jsonl")
        let verification = OvernightVerification(output: output, seconds: seconds)
        do { try verification.start() }
        catch { FileHandle.standardError.write(Data("Overnight verification failed: \(error)\n".utf8)); exit(1) }
        withExtendedLifetime(verification) { NSApp.run() }

    case .snapshot:
        let collector = MacSignalCollector()
        printJSON(collector.snapshot())

    case .snapshotWithoutAccessibility:
        let collector = MacSignalCollector(useAccessibility: false)
        printJSON(collector.snapshot())

    case let .watch(seconds):
        let collector = MacSignalCollector { event in
            printJSON(["event": event, "at": ISO8601DateFormatter().string(from: Date())])
        }
        printJSON(collector.activitySnapshot())
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                printJSON(collector.activitySnapshot())
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))

    case let .watchContext(seconds):
        let collector = MacSignalCollector { event in
            printJSON(["event": event, "at": ISO8601DateFormatter().string(from: Date())])
        }
        printJSON(collector.snapshot())
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                printJSON(collector.snapshot())
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))

    case let .overlay(textVariant):
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let collector = MacSignalCollector()
        let activeID = collector.snapshot().activeDisplayID
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == activeID
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let overlay = HorizonOverlay(screen: screen, textVariant: textVariant)
        withExtendedLifetime(overlay) {
            overlay.show()
            application.run()
        }

    case let .verifyOverlay(textVariant):
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let frontmostPIDBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let collector = MacSignalCollector()
        let activeID = collector.snapshot().activeDisplayID
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == activeID
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let overlay = HorizonOverlay(screen: screen, textVariant: textVariant)
        overlay.show(fadeIn: 0.05, hold: 2, fadeOut: 0.05)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
            MainActor.assumeIsolated {
                let frontmostPIDAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
                printJSON(overlay.verification(
                    frontmostPIDBefore: frontmostPIDBefore,
                    frontmostPIDAfter: frontmostPIDAfter
                ))
                overlay.dismiss()
                NSApplication.shared.terminate(nil)
            }
        }
        withExtendedLifetime(overlay) {
            application.run()
        }

    case let .verifyBundledOverlay(textVariant):
        let frontmostPIDBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let application = NSApplication.shared
        let collector = MacSignalCollector()
        let activeID = collector.snapshot().activeDisplayID
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == activeID
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let overlay = HorizonOverlay(screen: screen, textVariant: textVariant)
        overlay.show(fadeIn: 0.05, hold: 2, fadeOut: 0.05)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
            MainActor.assumeIsolated {
                let frontmostPIDAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
                printJSON(overlay.verification(
                    frontmostPIDBefore: frontmostPIDBefore,
                    frontmostPIDAfter: frontmostPIDAfter
                ))
                overlay.dismiss()
                NSApplication.shared.terminate(nil)
            }
        }
        withExtendedLifetime(overlay) {
            application.run()
        }

    case let .renderVisualMatrix(outputDirectory):
        _ = NSApplication.shared
        do {
            let urls = try HorizonOverlay.renderVisualMatrix(
                to: URL(fileURLWithPath: outputDirectory, isDirectory: true)
            )
            printJSON(["files": urls.map(\.path)])
        } catch {
            FileHandle.standardError.write(Data("visual matrix error: \(error)\n".utf8))
            exit(1)
        }

    case .verifyAutomaticReminder:
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let verification = AutomaticReminderVerification()
        verification.start()
        withExtendedLifetime(verification) { application.run() }

    case .verifyPhotoLibrary:
        do {
            let results = try PhotoLibrary.verifyLibrary()
            printJSON(results)
            if results.values.contains(false) { exit(1) }
        } catch {
            FileHandle.standardError.write(Data("Photo library verification failed: \(error)\n".utf8))
            exit(1)
        }

    case .verifyCurtain:
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let overlay = HorizonOverlay(screen: NSScreen.main ?? NSScreen.screens[0])
        overlay.show(terminateApplicationOnCompletion: false)
        let started = ProcessInfo.processInfo.systemUptime
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            MainActor.assumeIsolated {
                var sample = overlay.curtainSample()
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                sample["elapsedSeconds"] = elapsed
                printJSON(sample)
                if elapsed >= 3.5 {
                    application.terminate(nil)
                }
            }
        }
        withExtendedLifetime(overlay) { application.run() }

    case .reviewReservoir:
        do { printJSON(try renderReservoirReview()) }
        catch { FileHandle.standardError.write(Data("Review failed: \(error)\n".utf8)); exit(1) }
    case .fillReservoir:
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            var results: [String: Int] = [:]
            var failed = false
            for category in ImageCategory.allCases {
                if OnlineReservoir.shared.store.batch(category) == nil || (CommandLine.arguments.contains("--replace") && CommandLine.arguments.contains(category.rawValue)) {
                    FileHandle.standardError.write(Data("Downloading \(category.rawValue)…\n".utf8))
                    do { try await OnlineReservoir.shared.update(category) }
                    catch { failed = true; FileHandle.standardError.write(Data("\(category.rawValue): \(error)\n".utf8)) }
                }
                results[category.rawValue] = OnlineReservoir.shared.files(category).count
                FileHandle.standardError.write(Data("\(category.rawValue): \(results[category.rawValue]!)/10\n".utf8))
            }
            printJSON(results)
            exit(!failed && results.values.allSatisfy { $0 == 10 } ? 0 : 1)
        }
        NSApplication.shared.run()

    case .previewMenu:
        let instance = ApplicationInstance()
        do { guard try instance.acquire() else { return } }
        catch {
            FileHandle.standardError.write(Data("Unable to acquire application lock: \(error)\n".utf8))
            exit(1)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let controller = PreviewMenuController(automaticReminders: true)
        if CommandLine.arguments.contains("--settings") { DispatchQueue.main.async { controller.openSettings() } }
        if CommandLine.arguments.contains("--choose-categories") {
            DispatchQueue.main.async { controller.chooseCategories() }
        }
        if CommandLine.arguments.contains("--choose-system-photos") {
            DispatchQueue.main.async { controller.chooseSystemPhotos() }
        }
        withExtendedLifetime((instance, controller)) {
            application.run()
        }

    case .verifyPreviewMenu:
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let controller = PreviewMenuController()
        let frontmostPIDBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let overlay = controller.showPreview() else {
            FileHandle.standardError.write(Data("preview menu could not select a screen\n".utf8))
            exit(1)
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
            MainActor.assumeIsolated {
                let overlayResult = overlay.verification(
                    frontmostPIDBefore: frontmostPIDBefore,
                    frontmostPIDAfter: NSWorkspace.shared.frontmostApplication?.processIdentifier
                )
                printJSON(PreviewMenuVerification(
                    hasStatusItemButton: controller.hasStatusItemButton,
                    hasTemplateIcon: controller.hasTemplateIcon,
                    menuItemTitles: controller.menuItemTitles,
                    overlay: overlayResult
                ))
                application.terminate(nil)
            }
        }
        withExtendedLifetime((controller, overlay)) {
            application.run()
        }

    case .verifySyntheticTransitions:
        var events: [String] = []
        let collector = MacSignalCollector { event in
            events.append(event)
        }
        let center = NSWorkspace.shared.notificationCenter

        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        let sessionInactive = collector.activitySnapshot().sessionInactive
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let sessionActive = !collector.activitySnapshot().sessionInactive

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        let sleeping = collector.activitySnapshot().systemSleeping
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let awake = !collector.activitySnapshot().systemSleeping

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        let finalState = collector.activitySnapshot()
        printJSON(SyntheticTransitionVerification(
            observedEvents: events,
            sessionTransitionPassed: sessionInactive && sessionActive,
            systemSleepTransitionPassed: sleeping && awake,
            displayNotificationHintsObserved: events.contains("display_sleep_notification")
                && events.contains("display_wake_notification"),
            finalStateRestored: !finalState.sessionInactive && !finalState.systemSleeping
        ))

    case .verifyIdleSignal:
        let collector = MacSignalCollector()
        printJSON(collector.idleSignalVerification())

    case .requestAccessibility:
        // The public constant's value is stable, while referencing the imported mutable
        // global trips Swift 6 strict-concurrency diagnostics.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        print(AXIsProcessTrustedWithOptions(options) ? "accessibility: trusted" : "accessibility: not trusted")

    case .help:
        print("""
        focus-break-probe

          --snapshot                  Print one privacy-minimal JSON signal snapshot (default)
          --snapshot-no-accessibility Verify the no-Accessibility fallback path
          --watch [seconds]           Print cheap activity snapshots and lifecycle events
          --watch-context [seconds]   Print full display/window context every second
          --overlay [32|36]           Preview the non-activating, click-through overlay
          --preview-reminder [32|36]  User-facing alias for one reminder preview
          --verify-overlay [32|36]    Print runtime overlay focus and input behavior
          --verify-bundled-overlay    Verify LSUIElement bundle behavior without policy override
          --render-visual-matrix DIR  Render 32/36 pt previews across five visual contexts
          --verify-overnight [seconds] Log actual system activity and a separate injected 45-minute wall-clock run
          --verify-automatic-reminder Verify real timer delivery with a temporary short interval
          --verify-photo-library     Verify formats, rotation, folder updates and fallback
          --verify-curtain           Sample the live curtain mask over 2.8 seconds
          --preview-menu              Run a preview-only menu bar app
          --verify-preview-menu       Verify the menu item and its overlay without user input
          --verify-synthetic-transitions
                                      Inject workspace notifications for wiring tests only
          --verify-lifecycle          Deprecated alias for --verify-synthetic-transitions
          --verify-idle-signal        Compare any-input idle with per-event diagnostics
          --request-accessibility     Ask macOS for Accessibility permission
          --help                      Show this help

          Add --output <path> to also write a single JSON result for LaunchServices tests.
        """)
    }
}

run()
