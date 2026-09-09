import AppKit
import ServiceManagement
import FocusBreakProbeCore

@MainActor
final class PreviewMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var currentOverlay: HorizonOverlay?
    private var categoryChooser: CategoryChooser?
    private var categoryTimer: Timer?
    private var collectionWindow: CollectionWindow?
    private var dailyChoiceButton: NSButton?
    private var quickCategoryItems: [NSMenuItem] = []
    private var photosPicker: SystemPhotoPicker?
    private let libraryStatus = NSMenuItem(title: "使用内置照片", action: nil, keyEquivalent: "")

    private let reminders = ReminderCoordinator()
    private var isConfigWindowOpen = false
    private let reminderStatus = NSMenuItem(title: "自动提醒：45 分钟", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停自动提醒", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "登录时启动", action: nil, keyEquivalent: "")
    private var actionFeedback: NSTextField?
    private(set) var lastActionFeedback = ""
    private var settingsWindow: NSWindow?
    private var settingsStatus: NSTextField?
    private var settingsLibraryStatus: NSTextField?
    private var settingsLoginStatus: NSTextField?
    private let dailyStatus = NSMenuItem(title: "每日照片：尚未配置", action: nil, keyEquivalent: "")
    private let dailySource = NSMenuItem(title: "照片来自 Pexels", action: nil, keyEquivalent: "")

    init(automaticReminders: Bool = false) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displayLayoutChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        statusItem.button?.image = Self.menuBarImage()
        statusItem.button?.toolTip = "Focus Break Assistant"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(reminderStatus)
        let quick = NSMenu(); quick.delegate = self
        let hint = NSMenuItem(title: "今日沿用上次选择 · 点击类型切换", action: nil, keyEquivalent: "")
        quick.addItem(hint)
        for (index, category) in ImageCategory.allCases.enumerated() {
            let item = NSMenuItem(title: category.title, action: #selector(toggleQuickCategory(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; quick.addItem(item); quickCategoryItems.append(item)
        }
        quick.addItem(.separator())
        let complete = NSMenuItem(title: "完整分类选择…", action: #selector(chooseCategories), keyEquivalent: "")
        complete.target = self; quick.addItem(complete)
        reminderStatus.submenu = quick
        reminderStatus.toolTip = "展开可快速切换图片类型，不打开窗口。"
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        let previewItem = NSMenuItem(
            title: "预览下一张",
            action: #selector(previewReminder),
            keyEquivalent: ""
        )
        previewItem.target = self
        menu.addItem(previewItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Focus Break Assistant",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        reminders.isUIBusy = { [weak self] in
            guard let self else { return true }
            return self.collectionWindow != nil || self.categoryChooser != nil || self.photosPicker != nil || self.isConfigWindowOpen || self.settingsWindow?.isVisible == true || self.currentOverlay != nil
        }
        reminders.onReminder = { [weak self] in self?.showPreview(automatic: true) != nil }
        reminders.onStatus = { [weak self] text in self?.reminderStatus.title = text; self?.settingsStatus?.stringValue = text
            self?.settingsLibraryStatus?.stringValue = (self?.libraryStatus.title ?? "") + "\n" + OnlineReservoir.shared.status }
        reminders.onSystemRest = { [weak self] in
            self?.currentOverlay?.dismiss()
            self?.currentOverlay = nil
        }
        libraryStatus.title = CategoryLibrary.shared.preferences.active ? "当前：分类图库" : PhotoLibrary.shared.folderName.map { "照片文件夹：\($0)" } ?? "当前：使用内置照片"
        refreshControls()
        if automaticReminders {
            // This release adopts the user's lightweight daily-choice preference once.
            if !UserDefaults.standard.bool(forKey: "lightweightChoiceMigration") {
                CategoryLibrary.shared.preferences.askDaily = false
                UserDefaults.standard.set(true, forKey: "lightweightChoiceMigration")
            }
            reminders.start()
            DailyPhotos.shared.stopUpdates()
            if !UserDefaults.standard.bool(forKey: "reservoirMigrationComplete") {
                if DailyPhotos.shared.selected { CategoryLibrary.shared.preferences.active = true }
                do {
                    try DailyPhotos.shared.clear()
                    UserDefaults.standard.set(true, forKey: "reservoirMigrationComplete")
                } catch { /* Retry cleanup on the next launch; personal originals are separate. */ }
            }
            OnlineReservoir.shared.start()
            DispatchQueue.main.async { [weak self] in self?.checkDailyChoice() }
            categoryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkDailyChoice() }
            }
        }
    }

    @objc private func displayLayoutChanged() {
        // Discard a stale window before it can remain on a disconnected or resized display.
        currentOverlay?.dismiss(); currentOverlay = nil
    }

    private func checkDailyChoice() {
        guard CategoryLibrary.shared.preferences.shouldAsk(), collectionWindow == nil, categoryChooser == nil,
              photosPicker == nil, !isConfigWindowOpen, settingsWindow?.isVisible != true, currentOverlay == nil else { return }
        let snapshot = MacSignalCollector().snapshot()
        guard !snapshot.sessionInactive, !snapshot.systemSleeping, snapshot.displaySleepState == .no, snapshot.focusedWindowFullScreen == .no else { return }
        chooseCategories()
    }
    @objc func chooseCategories() {
        if let categoryChooser { categoryChooser.show(); reportAction("已打开分类选择窗口，请在该窗口完成选择。"); return }
        guard !focusBlockingPicker() else { return }
        currentOverlay?.dismiss(); currentOverlay = nil
        CategoryLibrary.shared.preferences.markPresented()
        let chooser = CategoryChooser()
        chooser.onClose = { [weak self] in
            self?.categoryChooser = nil
            if self?.settingsWindow?.isVisible == true { NSApp.setActivationPolicy(.accessory) }
            self?.libraryStatus.title = CategoryLibrary.shared.preferences.active
                ? "今日图库：" + CategoryLibrary.shared.preferences.categories.map(\.title).joined(separator: "、")
                : "沿用当前图片来源"
            self?.refreshControls()
        }
        categoryChooser = chooser
        chooser.show()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshControls() }

    private func refreshControls() {
        let online = OnlineReservoir.shared
        dailyStatus.title = "\(online.status) · \(online.store.bytes() / 1_024 / 1_024) MB"
        dailySource.title = online.currentImage.map { "\($0.provider) · \($0.license)（查看来源）" } ?? "查看图片来源网站"

        let preferences = CategoryLibrary.shared.preferences
        dailyChoiceButton?.state = preferences.askDaily ? .on : .off
        for item in quickCategoryItems {
            item.state = preferences.active && preferences.categories.contains(ImageCategory.allCases[item.tag]) ? .on : .off
        }
        statusItem.button?.toolTip = "Focus Break Assistant · " + preferences.categories.map(\.title).joined(separator: "、") + "（菜单倒计时可展开切换）"
        pauseItem.title = reminders.isPaused ? "恢复自动提醒" : "暂停自动提醒"
        reminders.publishStatus()
        settingsLibraryStatus?.stringValue = libraryStatus.title + "\n" + dailyStatus.title
        settingsLoginStatus?.stringValue = Bundle.main.bundleURL.pathExtension != "app" ? "登录启动需要从打包后的 App 设置。" :
            SMAppService.mainApp.status == .enabled ? "登录启动已开启" :
            SMAppService.mainApp.status == .requiresApproval ? "等待系统批准登录启动" : "登录启动已关闭"
        loginItem.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
    }

    @objc private func useDaily() {
        UserDefaults.standard.set(false, forKey: "favoritesOnly")
        CategoryLibrary.shared.preferences.active = true
        libraryStatus.title = "当前：分类在线图库"
        reportAction("已切换到分类在线图库，下次提醒或预览生效。")
        refreshControls()
    }
    @objc private func refreshDaily() {
        OnlineReservoir.shared.refresh(manual: true) { [weak self] message in
            self?.reportAction(message)
            self?.refreshControls()
        }
    }
    @objc private func resumeReservoir() { OnlineReservoir.shared.setEnabled(true); reportAction("每日更新已开启；今天已更新的图片不会重复下载。"); refreshControls() }
    @objc private func stopDaily() { OnlineReservoir.shared.setEnabled(false); reportAction("每日更新已关闭，现有图片保留；仍可手动检查。"); refreshControls() }
    @objc private func openReservoir() {
        let root = OnlineReservoir.shared.store.root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            reportAction(NSWorkspace.shared.open(root) ? "已在访达打开图库和许可记录。" : "未能打开图库目录，请重试。")
        } catch { reportAction("未能打开图库目录：" + error.localizedDescription) }
    }
    @objc private func openPhotoSource() {
        guard let image = OnlineReservoir.shared.currentImage else {
            reportAction("尚未显示在线图片。请先预览分类在线图库，再查看该图片的来源。")
            return
        }
        reportAction(NSWorkspace.shared.open(image.source) ? "已在浏览器打开图片来源。" : "未能打开来源链接，请检查默认浏览器。")
    }

    @objc private func togglePause() {
        reminders.togglePause()
        if reminders.isPaused { currentOverlay?.dismiss(); currentOverlay = nil }
        refreshControls()
    }

    @objc private func changeInterval(_ sender: NSPopUpButton) {
        reminders.changeInterval(sender.selectedTag())
        refreshControls()
    }

    @objc private func toggleLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            isConfigWindowOpen = true
            NSApplication.shared.setActivationPolicy(.accessory)
            defer {
                NSApplication.shared.setActivationPolicy(self.settingsWindow?.isVisible == true ? .accessory : .prohibited)
                isConfigWindowOpen = false
            }
            let alert = NSAlert(error: error)
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText += "\n请从固定位置运行 App；建议先放入‘应用程序’文件夹。"
            alert.runModal()
        }
        refreshControls()
    }

    @objc private func previewReminder() {
        _ = showPreview()
    }

    @objc func chooseSystemPhotos() {
        if let photosPicker { photosPicker.bringToFront(); reportAction("已打开系统照片选择窗口，请在该窗口继续。"); return }
        guard !focusBlockingPicker() else { return }
        currentOverlay?.dismiss()
        currentOverlay = nil
        let picker = SystemPhotoPicker { [weak self] count, failed in
            guard let self else { return }
            defer {
                self.photosPicker = nil
                self.refreshControls()
                NSApplication.shared.setActivationPolicy(self.settingsWindow?.isVisible == true ? .accessory : .prohibited)
            }
            if count > 0 {
                do {
                    try PhotoLibrary.shared.selectFolder(PhotoImportStore.directory)
                    self.libraryStatus.title = "已加入 \(count) 张图库照片"
                } catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = "照片已保存，但切换照片库失败，请重试"
                    alert.runModal()
                    return
                }
            }
            if failed > 0 {
                let alert = NSAlert()
                alert.messageText = count > 0 ? "已导入 \(count) 张，\(failed) 张未能导入" : "未能导入所选照片"
                alert.informativeText = "请检查 iCloud 照片是否已下载，再重新选择。成功导入的照片已保存在本机。"
                alert.runModal()
            }
        }
        photosPicker = picker
        picker.show()
    }

    @objc private func chooseFolder() {
        guard !focusBlockingPicker() else { return }
        isConfigWindowOpen = true
        defer { isConfigWindowOpen = false; refreshControls() }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        defer { NSApplication.shared.setActivationPolicy(self.settingsWindow?.isVisible == true ? .accessory : .prohibited) }
        let picker = NSOpenPanel()
        picker.title = "选择照片文件夹"
        picker.message = "支持 JPG、PNG、HEIC；读取文件夹中的照片，不会修改原图。"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { reportAction("已取消文件夹选择，图片来源未改变。"); return }
        do {
            try PhotoLibrary.shared.selectFolder(url)
            libraryStatus.title = PhotoLibrary.shared.status
            reportAction("已选择文件夹，下次提醒或预览生效。")
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法保存照片文件夹，请重新选择"
            alert.runModal()
        }
    }

    @objc private func useBuiltIn() {
        guard !focusBlockingPicker() else { return }
        PhotoLibrary.shared.useBuiltIn()
        libraryStatus.title = "当前：使用内置照片"
        reportAction("已切换到内置照片，下次提醒或预览生效。")
        refreshControls()
    }

    func showPreview(automatic: Bool = false) -> HorizonOverlay? {
        guard categoryChooser == nil, photosPicker == nil, let screen = activeScreen() else { return nil }
        currentOverlay?.dismiss()
        let overlay = HorizonOverlay(screen: screen, textVariant: .prominent)
        libraryStatus.title = PhotoLibrary.shared.status
        currentOverlay = overlay
        overlay.addControls(snooze: automatic ? { [weak self] in self?.reminders.snooze() } : nil,
                            skip: automatic ? { [weak self] in self?.reminders.skip() } : nil,
                            beginBreak: automatic ? { [weak self] in self?.reminders.beginBreak() } : nil)
        let savedHold = UserDefaults.standard.integer(forKey: "reminderHoldSeconds")
        overlay.onTimeout = { [weak self] in
            if automatic { self?.reminders.finishReminder(expired: true) }
        }
        overlay.show(hold: [15, 30, 60, 120].contains(savedHold) ? Double(savedHold) : 30,
                     terminateApplicationOnCompletion: false) { [weak self] in
            if automatic { self?.reminders.finishReminder(expired: false) }
            self?.currentOverlay = nil
        }
        return overlay
    }

    var hasStatusItemButton: Bool {
        statusItem.button != nil
    }

    var hasTemplateIcon: Bool {
        statusItem.button?.image?.isTemplate == true
    }

    var menuItemTitles: [String] {
        statusItem.menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
    }

    @objc func openSettings() {
        NSApp.setActivationPolicy(.accessory)
        currentOverlay?.dismiss()
        refreshControls()
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        NSApp.setActivationPolicy(.accessory)
        let settingsHeight = min(620, (NSScreen.main?.visibleFrame.height ?? 660) - 40)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: settingsHeight),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Focus Break Assistant 设置"
        window.isReleasedWhenClosed = false
        let tabs = NSTabView(frame: NSRect(x: 20, y: 72, width: 520, height: settingsHeight - 92))
        func page(_ title: String) -> NSStackView {
            let item = NSTabViewItem(identifier: title); item.label = title
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true
            let stack = SettingsStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = stack
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
            item.view = scroll; tabs.addTabViewItem(item); return stack
        }
        func button(_ title: String, _ action: Selector, _ stack: NSStackView) {
            stack.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        let reminder = page("提醒")
        let status = NSTextField(labelWithString: reminderStatus.title)
        settingsStatus = status; reminder.addArrangedSubview(status)
        reminder.addArrangedSubview(NSTextField(labelWithString: "连续使用多久后提醒（更改后重新计时）"))
        let interval = NSPopUpButton(); interval.target = self; interval.action = #selector(changeInterval(_:))
        for minutes in [30, 45, 60, 90] { interval.addItem(withTitle: "\(minutes) 分钟"); interval.lastItem?.tag = minutes }
        interval.selectItem(withTag: reminders.minutes); reminder.addArrangedSubview(interval)
        reminder.addArrangedSubview(NSTextField(labelWithString: "提醒停留时间"))
        let hold = NSPopUpButton(); hold.target = self; hold.action = #selector(changeHold(_:))
        for seconds in [15, 30, 60, 120] { hold.addItem(withTitle: "\(seconds) 秒"); hold.lastItem?.tag = seconds }
        let saved = UserDefaults.standard.integer(forKey: "reminderHoldSeconds")
        hold.selectItem(withTag: [15, 30, 60, 120].contains(saved) ? saved : 30); reminder.addArrangedSubview(hold)
        let retry = NSButton(checkboxWithTitle: "未处理时，5 分钟后再提醒一次（最多追加一次）", target: self, action: #selector(toggleUnansweredRetry(_:)))
        retry.state = UserDefaults.standard.bool(forKey: "retryUnansweredReminder") ? .on : .off
        reminder.addArrangedSubview(retry)
        reminder.addArrangedSubview(NSTextField(wrappingLabelWithString: "稍后 5 分钟：继续使用 5 分钟后重试。\n跳过本次：重新计算完整提醒间隔。\n开始休息：休息 5 分钟后开始新一轮。\nEsc 或跳过后重新计时；未处理默认重新计时。\n无操作 3 分钟暂停，5 分钟视为休息并重置；睡眠后重新计时。"))
        reminder.addArrangedSubview(NSTextField(labelWithString: "提醒文字位置（下一张生效）"))
        let position = NSPopUpButton(); position.addItems(withTitles: ["中央", "下方"])
        position.selectItem(at: ReminderPresentation().position == .center ? 0 : 1)
        position.target = self; position.action = #selector(changeTextPosition(_:)); reminder.addArrangedSubview(position)
        let brief = NSButton(checkboxWithTitle: "只显示简短提醒", target: self, action: #selector(toggleBrief(_:)))
        brief.state = ReminderPresentation().brief ? .on : .off; reminder.addArrangedSubview(brief)
        reminder.addArrangedSubview(NSTextField(wrappingLabelWithString: "文字使用实心白字和柔和阴影，背景保持透明。下方位置可减少遮挡脸部；不会自动识别人脸。"))
        let library = page("图片库")
        let libraryLabel = NSTextField(wrappingLabelWithString: libraryStatus.title + "\n" + dailyStatus.title)
        settingsLibraryStatus = libraryLabel; library.addArrangedSubview(libraryLabel)
        let ask = NSButton(checkboxWithTitle: "每天显示完整分类选择页（默认关闭）", target: self, action: #selector(toggleDailyChoice(_:)))
        dailyChoiceButton = ask
        ask.state = CategoryLibrary.shared.preferences.askDaily ? .on : .off; library.addArrangedSubview(ask)
        library.addArrangedSubview(NSTextField(wrappingLabelWithString: "默认沿用上次分类。在菜单倒计时上展开类型列表即可切换，不会每天抢焦点。"))
        for (title, action) in [
            ("收藏与已屏蔽图片…", #selector(openCollection)),
            ("使用收藏图库", #selector(useFavorites)),
            ("分类与每日选择…", #selector(chooseCategories)),
            ("选择本地照片文件夹…", #selector(chooseFolder)),
            ("从系统照片图库选择…", #selector(chooseSystemPhotos)),
            ("使用内置照片", #selector(useBuiltIn)),
            ("使用分类在线图库", #selector(useDaily)),
            ("立即检查在线更新", #selector(refreshDaily)),
            ("恢复每日整批更新", #selector(resumeReservoir)),
            ("关闭每日更新", #selector(stopDaily)),
            ("打开图库和许可记录…", #selector(openReservoir)),
            ("查看当前在线图片来源", #selector(openPhotoSource))
        ] { button(title, action, library) }
        let general = page("通用")
        button("切换登录时启动", #selector(toggleLogin), general)
        let loginLabel = NSTextField(wrappingLabelWithString: "")
        settingsLoginStatus = loginLabel; general.addArrangedSubview(loginLabel)
        refreshControls()
        let feedback = NSTextField(wrappingLabelWithString: lastActionFeedback.isEmpty ? "选择图片来源后，下次提醒或预览生效。" : lastActionFeedback)
        feedback.frame = NSRect(x: 28, y: 12, width: 504, height: 48)
        feedback.setAccessibilityIdentifier("libraryActionFeedback")
        actionFeedback = feedback
        window.contentView?.addSubview(feedback)
        window.contentView?.addSubview(tabs); window.center()
        settingsWindow = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleQuickCategory(_ sender: NSMenuItem) {
        let preferences = CategoryLibrary.shared.preferences
        let category = ImageCategory.allCases[sender.tag]
        var selected = preferences.categories
        if !preferences.active || UserDefaults.standard.bool(forKey: "favoritesOnly") { selected = [category] }
        else if selected.contains(category) {
            guard selected.count > 1 else { NSSound.beep(); return }
            selected.removeAll { $0 == category }
        } else { selected.append(category) }
        preferences.categories = selected; preferences.active = true
        UserDefaults.standard.set(false, forKey: "favoritesOnly")
        libraryStatus.title = "今日图库：" + preferences.categories.map(\.title).joined(separator: "、")
        refreshControls()
    }
    @objc private func toggleDailyChoice(_ sender: NSButton) { CategoryLibrary.shared.preferences.askDaily = sender.state == .on }
    @objc private func changeTextPosition(_ sender: NSPopUpButton) { ReminderPresentation().position = sender.indexOfSelectedItem == 0 ? .center : .bottom }
    @objc private func toggleBrief(_ sender: NSButton) { ReminderPresentation().brief = sender.state == .on }
    @objc private func useFavorites() {
        guard !PhotoCuration.shared.favorites.isEmpty else { reportAction("还没有收藏图片。请先在提醒或预览中点击“收藏”，当前图片来源未改变。"); return }
        UserDefaults.standard.set(true, forKey: "favoritesOnly")
        reportAction("已切换到收藏图库，下次提醒或预览生效。")
        libraryStatus.title = PhotoCuration.shared.favorites.isEmpty ? "收藏暂无图片，暂沿用现有图库" : "当前：收藏图库"
        refreshControls()
    }
    @objc private func openCollection() {
        currentOverlay?.dismiss()
        if let collectionWindow { collectionWindow.show(); return }
        let controller = CollectionWindow()
        controller.onClose = { [weak self] in self?.collectionWindow = nil; self?.refreshControls() }
        collectionWindow = controller; controller.show()
    }

    private func reportAction(_ message: String) {
        lastActionFeedback = message
        actionFeedback?.stringValue = message
    }

    private func focusBlockingPicker() -> Bool {
        if let categoryChooser {
            categoryChooser.show()
            reportAction("请先完成或关闭分类选择窗口，再执行此操作。")
            return true
        }
        if let photosPicker {
            photosPicker.bringToFront()
            reportAction("请先完成或关闭系统照片选择窗口，再执行此操作。")
            return true
        }
        if isConfigWindowOpen { reportAction("请先完成当前文件夹选择或对话框。"); return true }
        return false
    }

    @objc private func toggleUnansweredRetry(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "retryUnansweredReminder")
    }

    @objc private func changeHold(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.selectedTag(), forKey: "reminderHoldSeconds")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func activeScreen() -> NSScreen? {
        let activeDisplayID = MacSignalCollector().snapshot().activeDisplayID
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                == activeDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: 2.5, y: 9))
            path.line(to: NSPoint(x: 7.2, y: 9))
            path.move(to: NSPoint(x: 10.8, y: 9))
            path.line(to: NSPoint(x: 15.5, y: 9))
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
