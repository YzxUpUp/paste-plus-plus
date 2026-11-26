import AppKit
import ApplicationServices
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Appearance: String, CaseIterable {
        case system
        case light
        case dark

        static let preferenceKey = "interfaceAppearance"

        var title: String {
            switch self {
            case .system: "跟随系统"
            case .light: "明亮"
            case .dark: "黑暗"
            }
        }

        var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    private let history = History(file: URL.applicationSupportDirectory
        .appending(path: "Paste++/history.json"))
    private let clipboard = Clipboard()
    private let hotKey = HotKey()
    private var shortcut = Shortcut.load()
    private var autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool ?? true
    private var appearance = Appearance(
        rawValue: UserDefaults.standard.string(forKey: Appearance.preferenceKey) ?? ""
    ) ?? .system
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var displayedHistoryCount: Int?
    private lazy var settingsMenu = makeSettingsMenu()
    private lazy var window = HistoryWindow(history: history, settingsMenu: settingsMenu)
    private var lastExternalApp: NSRunningApplication?
    private var pasteTarget: NSRunningApplication?
    private var timer: Timer?
    private var autoPasteAuthorizationTimer: Timer?
    private var hotKeyStatus: OSStatus = noErr
    private let notice = NSPopover()
    private var noticeTimeout: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = appearance.appKitAppearance
        lastExternalApp = frontmostExternalApp
        configureStatusItem()

        window.onChoose = { [weak self] clip in self?.paste(clip) }
        window.onCancel = { [weak self] in self?.returnToOriginalApp() }
        do {
            try history.load()
        } catch {
            showNotice("历史记录读取失败。")
        }
        updateStatusIcon()
        do {
            try history.loadFavorites()
        } catch {
            showNotice("收藏读取失败。")
        }

        hotKeyStatus = registerShortcut(shortcut)
        if hotKeyStatus != noErr {
            showNotice("无法注册 \(shortcut.displayName)。可以从菜单栏打开历史记录。")
        }

        let poll = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        autoPasteAuthorizationTimer?.invalidate()
        hotKey.unregister()
    }

    func menuWillOpen(_ menu: NSMenu) {
        notice.performClose(nil)
        if let frontmostExternalApp {
            lastExternalApp = frontmostExternalApp
        }
        if let unavailable = menu.items.first(where: { $0.tag == 1 }) {
            unavailable.title = "快捷键 \(shortcut.displayName) 不可用"
            unavailable.isHidden = hotKeyStatus == noErr
        }
        if let autoPaste = menu.items.first(where: { $0.tag == 2 }) {
            autoPaste.title = autoPasteEnabled ? "关闭自动粘贴" : "启用自动粘贴"
        }
        menu.items.first(where: { $0.tag == 3 })?.isHidden = !clipboard.readDenied
        if let authorization = menu.items.first(where: { $0.tag == 4 }) {
            authorization.isHidden = !autoPasteEnabled || CGPreflightPostEventAccess()
        }
    }

    private func configureStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("打开历史记录", #selector(openHistory)))
        let hotKeyNote = menuItem("", nil)
        hotKeyNote.tag = 1
        menu.addItem(hotKeyNote)
        let readAccess = menuItem("剪贴板读取已关闭", nil)
        readAccess.tag = 3
        menu.addItem(readAccess)
        menu.addItem(.separator())
        menu.addItem(menuItem("设置…", #selector(openSettings)))
        menu.addItem(menuItem("退出 Paste++", #selector(quit)))
        status.menu = menu
    }

    private func updateStatusIcon() {
        let count = history.clips.count
        guard count != displayedHistoryCount, let button = status.button else { return }
        button.image = HistoryStatusIcon.make(count: count)
        let description = "Paste++，\(count) 条历史记录"
        button.toolTip = description
        button.setAccessibilityLabel(description)
        displayedHistoryCount = count
    }

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu(title: "设置")
        menu.delegate = self
        menu.addItem(menuItem("快捷键…", #selector(configureShortcut)))
        menu.addItem(appearanceMenuItem())
        menu.addItem(menuItem("历史记录上限…", #selector(configureHistoryLimit)))
        let access = menuItem("启用自动粘贴", #selector(toggleAutoPaste))
        access.tag = 2
        menu.addItem(access)
        let authorization = menuItem("授权自动粘贴…", #selector(authorizeAutoPaste))
        authorization.tag = 4
        menu.addItem(authorization)
        menu.addItem(.separator())
        menu.addItem(menuItem("清空历史记录…", #selector(clearHistory)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func appearanceMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "外观")
        for option in Appearance.allCases {
            let item = menuItem(option.title, #selector(selectAppearance(_:)))
            item.representedObject = option.rawValue
            item.state = option == appearance ? .on : .off
            submenu.addItem(item)
        }
        let item = menuItem("外观", nil)
        item.submenu = submenu
        return item
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let selected = Appearance(rawValue: value) else { return }
        appearance = selected
        NSApp.appearance = selected.appKitAppearance
        UserDefaults.standard.set(selected.rawValue, forKey: Appearance.preferenceKey)
        for item in sender.menu?.items ?? [] {
            item.state = item === sender ? .on : .off
        }
    }

    private var frontmostExternalApp: NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return front
    }

    @objc private func openHistory() {
        guard NSApp.modalWindow == nil else { return }
        notice.performClose(nil)
        if window.isVisible && NSApp.isActive {
            window.focus()
            return
        }
        pasteTarget = frontmostExternalApp ?? lastExternalApp
        lastExternalApp = pasteTarget
        pollClipboard()
        window.show()
    }

    @objc private func openSettings() {
        guard NSApp.modalWindow == nil else { return }
        openHistory()
        DispatchQueue.main.async { [weak self] in self?.window.showSettings() }
    }

    private func pollClipboard() {
        guard let text = clipboard.readChange() else { return }
        do {
            try history.record(text)
        } catch {
            if !notice.isShown {
                showNotice("历史记录写入失败。当前记录暂存在内存中。")
            }
        }
        updateStatusIcon()
        if window.isVisible { window.refresh() }
    }

    @objc private func configureHistoryLimit() {
        let previousApp = frontmostExternalApp ?? pasteTarget ?? lastExternalApp
        NSApp.activate()
        defer { restoreFocus(afterSettings: previousApp) }

        let range = History.allowedLimits
        let rangeDescription = "\(range.lowerBound) 到 \(range.upperBound)"
        let alert = NSAlert()
        alert.messageText = "历史记录上限"
        alert.informativeText = "设置要保留的历史条数，范围为 \(rangeDescription)。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1B}"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = String(history.limit)
        input.setAccessibilityLabel("历史记录上限")
        alert.accessoryView = input

        while true {
            alert.layout()
            alert.window.initialFirstResponder = input
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let limit = Int(text), range.contains(limit) else {
                alert.informativeText = "请输入 \(rangeDescription) 之间的整数。"
                continue
            }
            guard limit != history.limit else { return }
            if history.clips.count > limit {
                let confirm = NSAlert()
                confirm.messageText = "降低历史记录上限？"
                confirm.informativeText = "将保留最近 \(limit) 条历史，超出的旧记录会被删除。收藏会保留。"
                confirm.addButton(withTitle: "取消").keyEquivalent = "\u{1B}"
                confirm.addButton(withTitle: "降低上限").hasDestructiveAction = true
                guard confirm.runModal() == .alertSecondButtonReturn else { continue }
            }
            do {
                try history.setLimit(limit)
                updateStatusIcon()
                window.refresh()
            } catch {
                showNotice("保存历史记录上限失败。请重试。")
            }
            return
        }
    }

    private func registerShortcut(_ candidate: Shortcut) -> OSStatus {
        hotKey.register(candidate) { [weak self] in self?.openHistory() }
    }

    @objc private func configureShortcut() {
        let previousApp = frontmostExternalApp ?? pasteTarget ?? lastExternalApp
        NSApp.activate()
        defer { restoreFocus(afterSettings: previousApp) }

        ShortcutSettings.present(current: shortcut) { candidate in
            let result = registerShortcut(candidate)
            if result == noErr {
                shortcut = candidate
                hotKeyStatus = noErr
                candidate.save()
            }
            return result
        }
    }

    private func restoreFocus(afterSettings previousApp: NSRunningApplication?) {
        if window.isVisible {
            window.focus()
        } else {
            pasteTarget = previousApp
            returnToOriginalApp()
        }
    }

    @objc private func clearHistory() {
        let previousApp = frontmostExternalApp ?? pasteTarget ?? lastExternalApp
        window.hide()
        pasteTarget = previousApp
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "将删除最近复制的历史记录，收藏会保留。"
        alert.addButton(withTitle: "清空")
        let cancel = alert.addButton(withTitle: "取消")
        alert.buttons[0].keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        alert.buttons[0].hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try history.clear()
                clipboard.skipCurrentContents()
                updateStatusIcon()
                window.refresh(resetSelection: true)
            } catch {
                showNotice("清空失败。历史记录仍然保留。")
            }
        }
        returnToOriginalApp()
    }

    @objc private func toggleAutoPaste() {
        autoPasteEnabled.toggle()
        UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled")
        if autoPasteEnabled {
            authorizeAutoPaste()
        } else {
            stopWatchingAutoPasteAuthorization()
        }
    }

    @objc private func authorizeAutoPaste() {
        guard autoPasteEnabled, !CGPreflightPostEventAccess() else { return }
        if !AXIsProcessTrusted(), !CGRequestPostEventAccess(),
           let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settings)
        }
        stopWatchingAutoPasteAuthorization()
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        let watch = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAutoPasteAuthorization(until: deadline) }
        }
        autoPasteAuthorizationTimer = watch
        RunLoop.main.add(watch, forMode: .common)
    }

    private func refreshAutoPasteAuthorization(until deadline: TimeInterval) {
        if CGPreflightPostEventAccess() || ProcessInfo.processInfo.systemUptime >= deadline {
            stopWatchingAutoPasteAuthorization()
            return
        }
        guard AXIsProcessTrusted(), NSApp.modalWindow == nil else { return }
        stopWatchingAutoPasteAuthorization()
        relaunchAfterAuthorization()
    }

    private func stopWatchingAutoPasteAuthorization() {
        autoPasteAuthorizationTimer?.invalidate()
        autoPasteAuthorizationTimer = nil
    }

    private func relaunchAfterAuthorization() {
        // A fresh process can pick up a grant when Core Graphics still reports the old result.
        let launcher = Process()
        launcher.executableURL = URL(filePath: "/bin/sh")
        launcher.arguments = ["-c", """
            for attempt in 1 2 3 4 5; do
                if ! kill -0 "$1" 2>/dev/null && /usr/bin/open -g -a "$2"; then
                    exit 0
                fi
                /bin/sleep 1
            done
            """, "pasteplusplus-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        do {
            try launcher.run()
            NSApp.terminate(nil)
        } catch {
            showNotice("辅助功能已授权。请重新打开 Paste++，让自动粘贴生效。")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func returnToOriginalApp() -> NSRunningApplication? {
        let target = pasteTarget
        pasteTarget = nil
        if let target, !target.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            NSApp.yieldActivation(to: target)
            target.activate(from: NSRunningApplication.current)
        }
        window.hide()
        return target
    }

    private func paste(_ clip: Clip) {
        pollClipboard()
        let change = clipboard.put(clip.text)
        let target = returnToOriginalApp()
        guard let change else {
            showNotice("写入剪贴板失败。请重新选择记录。")
            return
        }
        guard autoPasteEnabled else { return }
        guard CGPreflightPostEventAccess() else {
            showNotice("已复制，可按 ⌘V。请在 Paste++ 设置中选择「授权自动粘贴…」。")
            return
        }
        guard let target, !target.isTerminated else {
            showNotice("已复制。请切换到目标窗口并按 ⌘V。")
            return
        }
        pasteWhenActive(target, change: change, deadline: .now() + 1.5)
    }

    private func pasteWhenActive(_ target: NSRunningApplication, change: Int, deadline: DispatchTime,
                                 focusSettled: Bool = false) {
        guard autoPasteEnabled, !window.isVisible else { return }
        guard clipboard.changeCount == change else {
            showNotice("剪贴板已更新。请重新选择要粘贴的记录。")
            return
        }
        guard !target.isTerminated, DispatchTime.now() < deadline else {
            showNotice("已复制。请切换到目标窗口并按 ⌘V。")
            return
        }
        let targetIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
        guard targetIsFrontmost && focusSettled else {
            let delay: DispatchTimeInterval = targetIsFrontmost ? .milliseconds(100) : .milliseconds(50)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pasteWhenActive(target, change: change, deadline: deadline, focusSettled: targetIsFrontmost)
            }
            return
        }
        guard CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            showNotice("已复制，可按 ⌘V。请确认系统辅助功能权限。")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
    }

    private func showNotice(_ text: String) {
        guard let button = status.button, button.window != nil else { return }
        noticeTimeout?.cancel()
        notice.performClose(nil)
        let controller = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 62))
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = view.bounds.insetBy(dx: 16, dy: 13)
        label.autoresizingMask = [.width, .height]
        view.addSubview(label)
        controller.view = view
        notice.contentViewController = controller
        notice.behavior = .transient
        notice.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        let timeout = DispatchWorkItem { [weak self] in self?.notice.performClose(nil) }
        noticeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
