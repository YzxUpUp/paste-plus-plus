import AppKit
import ApplicationServices
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let history = History(file: URL.applicationSupportDirectory
        .appending(path: "Paste++/history.json"))
    private let clipboard = Clipboard()
    private let hotKey = HotKey()
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var window = HistoryWindow(history: history)
    private var lastExternalApp: NSRunningApplication?
    private var pasteTarget: NSRunningApplication?
    private var timer: Timer?
    private var hotKeyStatus: OSStatus = noErr
    private let notice = NSPopover()
    private var noticeTimeout: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lastExternalApp = frontmostExternalApp
        configureStatusItem()

        window.onChoose = { [weak self] clip in self?.paste(clip) }
        window.onCancel = { [weak self] in self?.returnToOriginalApp() }
        do {
            try history.load()
        } catch {
            showNotice("历史记录读取失败。")
        }
        do {
            try history.loadFavorites()
        } catch {
            showNotice("收藏读取失败。")
        }

        hotKeyStatus = hotKey.register { [weak self] in self?.openHistory() }
        if hotKeyStatus != noErr {
            showNotice("无法注册 ⌘⇧V。可以从菜单栏打开历史记录。")
        }

        let poll = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hotKey.unregister()
    }

    func menuWillOpen(_ menu: NSMenu) {
        notice.performClose(nil)
        if let frontmostExternalApp {
            lastExternalApp = frontmostExternalApp
        }
        menu.items.first(where: { $0.tag == 1 })?.isHidden = hotKeyStatus == noErr
        menu.items.first(where: { $0.tag == 2 })?.isHidden = AXIsProcessTrusted()
        menu.items.first(where: { $0.tag == 3 })?.isHidden = !clipboard.readDenied
    }

    private func configureStatusItem() {
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Paste++")
            button.toolTip = "Paste++"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("打开历史记录", #selector(openHistory)))
        let hotKeyNote = menuItem("快捷键 ⌘⇧V 不可用", nil)
        hotKeyNote.tag = 1
        menu.addItem(hotKeyNote)
        let access = menuItem("启用自动粘贴…", #selector(requestPasteAccess))
        access.tag = 2
        menu.addItem(access)
        let readAccess = menuItem("剪贴板读取已关闭", nil)
        readAccess.tag = 3
        menu.addItem(readAccess)
        menu.addItem(.separator())
        menu.addItem(menuItem("清空历史记录…", #selector(clearHistory)))
        menu.addItem(menuItem("退出 Paste++", #selector(quit)))
        status.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private var frontmostExternalApp: NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return front
    }

    @objc private func openHistory() {
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

    private func pollClipboard() {
        guard let text = clipboard.readChange() else { return }
        do {
            try history.record(text)
        } catch {
            if !notice.isShown {
                showNotice("历史记录写入失败。当前记录暂存在内存中。")
            }
        }
        if window.isVisible { window.refresh() }
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
                window.refresh(resetSelection: true)
            } catch {
                showNotice("清空失败。历史记录仍然保留。")
            }
        }
        returnToOriginalApp()
    }

    @objc private func requestPasteAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func returnToOriginalApp() -> NSRunningApplication? {
        let target = pasteTarget
        pasteTarget = nil
        window.hide()
        if let target, !target.isTerminated, !target.isActive {
            NSApp.yieldActivation(to: target)
            target.activate(from: NSRunningApplication.current)
        }
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
        guard AXIsProcessTrusted() else {
            showNotice("已复制，可按 ⌘V。通过菜单栏启用自动粘贴。")
            return
        }
        guard let target, !target.isTerminated else {
            showNotice("已复制。请切换到目标窗口并按 ⌘V。")
            return
        }
        pasteWhenActive(target, change: change, deadline: .now() + 1)
    }

    private func pasteWhenActive(_ target: NSRunningApplication, change: Int, deadline: DispatchTime) {
        guard clipboard.changeCount == change else {
            showNotice("剪贴板已更新。请重新选择要粘贴的记录。")
            return
        }
        guard !target.isTerminated, DispatchTime.now() < deadline else {
            showNotice("已复制。请切换到目标窗口并按 ⌘V。")
            return
        }
        guard target.isActive, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pasteWhenActive(target, change: change, deadline: deadline)
            }
            return
        }
        guard CGPreflightPostEventAccess(),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
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
