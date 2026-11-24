import AppKit
import Carbon

@MainActor
enum ShortcutSettings {
    static func present(current: Shortcut, apply: (Shortcut) -> OSStatus) {
        let instruction = "按下包含 ⌘、⌃ 或 ⌥ 的组合键。"
        let alert = NSAlert()
        alert.messageText = "打开历史记录的快捷键"
        alert.informativeText = instruction
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1B}"
        alert.addButton(withTitle: "恢复默认")

        let preview = NSTextField(labelWithString: current.displayName)
        preview.frame = NSRect(x: 0, y: 0, width: 240, height: 28)
        preview.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        alert.accessoryView = preview

        var candidate = current
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window,
                  !event.modifierFlags.intersection(Shortcut.primaryModifiers).isEmpty else { return event }
            guard !event.isARepeat else { return nil }
            guard let shortcut = Shortcut(event: event) else { return nil }
            guard !shortcut.isSystemPaste else {
                alert.informativeText = "⌘V 用于粘贴，请选择其他组合键。"
                alert.layout()
                return nil
            }
            candidate = shortcut
            preview.stringValue = shortcut.displayName
            alert.informativeText = instruction
            alert.layout()
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }

        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertThirdButtonReturn:
                candidate = .defaultShortcut
                preview.stringValue = candidate.displayName
            default:
                return
            }

            let status = apply(candidate)
            if status == noErr { return }
            alert.informativeText = status == eventHotKeyExistsErr
                ? "\(candidate.displayName) 已被占用，请选择其他组合键。"
                : "无法注册 \(candidate.displayName)，请选择其他组合键。"
        }
    }
}
