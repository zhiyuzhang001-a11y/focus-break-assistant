import AppKit
import UniformTypeIdentifiers
import FocusBreakProbeCore

@MainActor
final class CategoryChooser: NSObject, NSWindowDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 690), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let library = CategoryLibrary.shared
    private var choices: [ImageCategory: NSButton] = [:]
    private var previews: [ImageCategory: NSImageView] = [:]
    private var counts: [ImageCategory: NSTextField] = [:]
    private let ask = NSButton(checkboxWithTitle: "每天首次使用时询问", target: nil, action: nil)
    private let people = NSPopUpButton()
    private let message = NSTextField(wrappingLabelWithString: "空分类可导入图片；全部为空时临时使用内置风景。在线图库每类固定 10 张，共 60 张；每天整批替换。")
    var onClose: (() -> Void)?
    private var finished = false

    override init() {
        super.init()
        window.title = "今天想看什么？"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)
        ])
        let title = NSTextField(labelWithString: "今天想看什么？")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(labelWithString: "可以多选，提醒时从所选图库轮换。随时可在菜单栏更改。"))
        for row in 0..<2 {
            let rowStack = NSStackView(); rowStack.orientation = .horizontal; rowStack.spacing = 14
            for category in Array(ImageCategory.allCases)[(row * 3)..<(row * 3 + 3)] {
                let card = NSStackView(); card.orientation = .vertical; card.alignment = .leading; card.spacing = 6
                card.widthAnchor.constraint(equalToConstant: 204).isActive = true
                let preview = NSImageView(); preview.imageScaling = .scaleProportionallyUpOrDown
                preview.widthAnchor.constraint(equalToConstant: 204).isActive = true
                preview.heightAnchor.constraint(equalToConstant: 72).isActive = true
                previews[category] = preview; card.addArrangedSubview(preview)
                let choice = NSButton(checkboxWithTitle: category.title, target: nil, action: nil)
                choice.font = .systemFont(ofSize: 16, weight: .medium)
                choice.state = library.preferences.categories.contains(category) ? .on : .off
                choices[category] = choice; card.addArrangedSubview(choice)
                let count = NSTextField(labelWithString: ""); count.font = .systemFont(ofSize: 11)
                counts[category] = count; card.addArrangedSubview(count)
                let button = NSButton(title: "导入图片…", target: self, action: #selector(importImages(_:)))
                button.tag = ImageCategory.allCases.firstIndex(of: category)!
                card.addArrangedSubview(button)
                rowStack.addArrangedSubview(card)
                refresh(category)
            }
            stack.addArrangedSubview(rowStack)
        }
        let personRow = NSStackView(); personRow.orientation = .horizontal
        personRow.addArrangedSubview(NSTextField(labelWithString: "人物在线偏好："))
        people.addItems(withTitles: ["生活纪实", "运动", "时尚"])
        people.selectItem(withTitle: library.preferences.peopleStyle)
        personRow.addArrangedSubview(people); stack.addArrangedSubview(personRow)
        ask.state = library.preferences.askDaily ? .on : .off
        stack.addArrangedSubview(ask)
        message.font = .systemFont(ofSize: 12); message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 635
        stack.addArrangedSubview(message)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 12
        for (title, action) in [("沿用上次选择", #selector(usePrevious)), ("今天随机", #selector(randomize)), ("使用所选类型", #selector(apply))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            if title == "使用所选类型" { button.keyEquivalent = "\r" }
            buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons)
    }
    func show() {
        NSApp.setActivationPolicy(.accessory)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func refresh(_ category: ImageCategory) {
        let files = library.files(category)
        previews[category]?.image = files.lazy.compactMap { PhotoLibrary.decode($0) }.first
            ?? NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title)
        counts[category]?.stringValue = "在线 \(OnlineReservoir.shared.files(category).count)/10 · 自存 \(library.localFiles(category).count) 张"
    }
    @objc private func importImages(_ sender: NSButton) {
        let category = ImageCategory.allCases[sender.tag]
        let panel = NSOpenPanel()
        panel.title = "导入到「\(category.title)」"
        panel.message = "选择你有权使用的现成图片。复制到此分类图库，不改动原图；导入图片会长期保留。"
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let result = self.library.importFiles(panel.urls, category: category)
            self.message.stringValue = "已导入 \(result.success) 张，\(result.failed) 张失败。导入图片不计入在线缓存额度。"
            self.refresh(category)
            if result.success > 0 { self.choices[category]?.state = .on }
        }
    }
    @objc private func randomize() {
        let available = ImageCategory.allCases.filter { !library.files($0).isEmpty }
        guard let category = available.randomElement() else { return }
        for (key, choice) in choices { choice.state = key == category ? .on : .off }
        apply()
    }
    @objc private func usePrevious() {
        commit(library.preferences.categories)
    }
    @objc private func apply() {
        let selected = ImageCategory.allCases.filter { choices[$0]?.state == .on }
        guard !selected.isEmpty else { message.stringValue = "请至少选择一种类型，或点击“沿用上次选择”。"; return }
        commit(selected)
    }
    private func commit(_ categories: [ImageCategory]) {
        library.preferences.categories = categories
        library.preferences.peopleStyle = people.titleOfSelectedItem ?? "生活纪实"
        library.preferences.askDaily = ask.state == .on
        UserDefaults.standard.set(false, forKey: "favoritesOnly")
        library.preferences.active = true
        OnlineReservoir.shared.refresh()
        window.close()
    }
    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        // Closing without applying retains the prior source and choices.
        library.preferences.askDaily = ask.state == .on
        NSApp.setActivationPolicy(.prohibited)
        onClose?()
    }
}
