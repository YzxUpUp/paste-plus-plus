import AppKit
import Carbon

struct Shortcut: Codable {
    private static let preferenceKey = "historyShortcut"
    private static let modifiers: [(NSEvent.ModifierFlags, UInt32, String)] = [
        (.command, UInt32(cmdKey), "⌘"),
        (.control, UInt32(controlKey), "⌃"),
        (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧")
    ]
    static let primaryModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    static let defaultShortcut = Shortcut(keyCode: UInt16(kVK_ANSI_V),
                                          modifierMask: UInt32(cmdKey | shiftKey), keyName: "V")

    let keyCode: UInt16
    let modifierMask: UInt32
    let keyName: String

    var displayName: String {
        Self.modifiers.compactMap { _, bit, symbol in modifierMask & bit == 0 ? nil : symbol }
            .joined() + keyName
    }

    private init(keyCode: UInt16, modifierMask: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifierMask = modifierMask
        self.keyName = keyName
    }

    init?(event: NSEvent) {
        guard !event.modifierFlags.intersection(Self.primaryModifiers).isEmpty else { return nil }
        var mask: UInt32 = 0
        for (flag, bit, _) in Self.modifiers where event.modifierFlags.contains(flag) {
            mask |= bit
        }
        let specialKeys: [Int: String] = [
            kVK_Space: "空格", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥",
            kVK_Escape: "Esc", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"
        ]
        let name: String
        if let special = specialKeys[Int(event.keyCode)] {
            name = special
        } else if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
                  (0xF704...0xF726).contains(scalar.value) {
            name = "F\(scalar.value - 0xF703)"
        } else {
            let unmodified = event.characters(byApplyingModifiers: []) ?? ""
            let characters = unmodified.isEmpty ? event.charactersIgnoringModifiers ?? "" : unmodified
            name = characters.trimmingCharacters(in: .controlCharacters).uppercased()
        }
        guard !name.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifierMask: mask, keyName: name)
    }

    var isSystemPaste: Bool {
        modifierMask == UInt32(cmdKey) && keyName == "V"
    }

    func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifierMask == other.modifierMask
    }

    static func load(defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: preferenceKey),
              let saved = try? PropertyListDecoder().decode(Shortcut.self, from: data),
              saved.modifierMask & UInt32(cmdKey | controlKey | optionKey) != 0,
              saved.modifierMask & ~UInt32(cmdKey | controlKey | optionKey | shiftKey) == 0,
              !saved.keyName.isEmpty, !saved.isSystemPaste else { return defaultShortcut }
        return saved
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? PropertyListEncoder().encode(self) {
            defaults.set(data, forKey: Self.preferenceKey)
        }
    }
}

@MainActor
final class HotKey {
    private static let signature: OSType = 0x50707374
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var activeShortcut: Shortcut?
    private var activeID: UInt32 = 0
    private var action: (() -> Void)?

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> OSStatus {
        if handler == nil {
            let status = installHandler()
            guard status == noErr else { return status }
        }
        if activeShortcut?.matches(shortcut) == true {
            self.action = action
            return noErr
        }

        let nextID: UInt32 = activeID == 1 ? 2 : 1
        let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
        var nextRegistration: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifierMask, identifier,
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &nextRegistration)
        guard status == noErr else { return status }
        if let registration {
            let removed = UnregisterEventHotKey(registration)
            if removed != noErr {
                if let nextRegistration { UnregisterEventHotKey(nextRegistration) }
                return removed
            }
        }
        registration = nextRegistration
        activeID = nextID
        activeShortcut = shortcut
        self.action = action
        return noErr
    }

    private func installHandler() -> OSStatus {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == HotKey.signature, identifier.id == hotKey.activeID,
                      let action = hotKey.action else { return OSStatus(eventNotHandledErr) }
                action()
                return OSStatus(noErr)
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        activeShortcut = nil
        activeID = 0
        action = nil
    }
}
