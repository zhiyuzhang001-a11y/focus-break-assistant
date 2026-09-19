import AppKit
import Testing
@testable import FocusBreakProbe

@Suite(.serialized)
@MainActor
struct ReminderControlsTests {
    @Test func menuBarStateTracksReminderMeaning() {
        let suite = "ReminderControlsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ReminderCoordinator(defaults: defaults, intervalOverride: 45 * 60)

        #expect(coordinator.visualState == .working)
        coordinator.togglePause()
        #expect(coordinator.visualState == .paused)
        coordinator.togglePause()
        coordinator.snooze()
        #expect(coordinator.visualState == .upcoming)
        coordinator.beginBreak()
        #expect(coordinator.visualState == .resting)
    }

    @Test func settingsPagesAndMenu() throws {
        _ = NSApplication.shared
        let controller = PreviewMenuController()
        #expect(Array(controller.menuItemTitles.dropFirst()) == ["暂停自动提醒", "预览下一张", "设置…", "退出 Focus Break Assistant"] ||
                Array(controller.menuItemTitles.dropFirst()) == ["恢复自动提醒", "预览下一张", "设置…", "退出 Focus Break Assistant"])
        #expect(controller.statusVisualState == .working || controller.statusVisualState == .paused)
        #expect(controller.hasTemplateIcon)
        controller.openSettings()
        let window = try #require(NSApp.windows.first { $0.title == "Focus Break Assistant 设置" })
        defer { window.close() }
        let tabs = try #require(window.contentView?.subviews.compactMap { $0 as? NSTabView }.first)
        let feedback = try #require(window.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(!feedback.stringValue.isEmpty)
        #expect(feedback.frame.maxY <= tabs.frame.minY)
        #expect(tabs.tabViewItems.map(\.label) == ["提醒", "图片库", "通用"])
        for item in tabs.tabViewItems {
            tabs.selectTabViewItem(item)
            window.contentView?.layoutSubtreeIfNeeded()
            let stack = try #require((item.view as? NSScrollView)?.documentView as? NSStackView)
            #expect(!stack.arrangedSubviews.isEmpty)
            for control in stack.arrangedSubviews {
                #expect(control.frame.minY >= 0 && control.frame.maxY <= stack.bounds.height + 1)
            }
        }
    }

    @Test func reminderButtonsAndDismissAreIdempotent() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        for action in ["开始休息", "稍后 5 分钟", "跳过本次", "收起 · Esc", "Esc"] {
            var snoozes = 0, skips = 0, dismissals = 0, breaks = 0
            let overlay = HorizonOverlay(screen: screen)
            overlay.addControls(snooze: { snoozes += 1 }, skip: { skips += 1 }, beginBreak: { breaks += 1 })
            overlay.show(fadeIn: 0, hold: 120, terminateApplicationOnCompletion: false) { dismissals += 1 }
            let panel = try #require(NSApp.windows.first { $0 is HorizonPanel && $0.isVisible })
            let controls = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
            if action == "Esc" { panel.cancelOperation(nil) } else {
            if let popup = controls.arrangedSubviews.compactMap({ $0 as? NSPopUpButton }).first {
                let item = try #require(popup.menu?.items.first { $0.title == action })
                NSApp.sendAction(try #require(item.action), to: item.target, from: item)
            } else {
                let buttons = controls.arrangedSubviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
                try #require(buttons.first { $0.title == action }).performClick(nil)
            }
            }
            overlay.dismiss()
            #expect(dismissals == 1)
            #expect(breaks == (action == "开始休息" ? 1 : 0))
            #expect(snoozes == (action == "稍后 5 分钟" ? 1 : 0))
            #expect(skips == (action == "跳过本次" ? 1 : 0))
            #expect(!panel.isVisible)
        }
    }
}
