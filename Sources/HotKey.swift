import Carbon

@MainActor
final class HotKey {
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) -> OSStatus {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }

        let identifier = EventHotKeyID(signature: 0x50707374, id: 1)
        let result = RegisterEventHotKey(
            UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
            identifier, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &registration
        )
        if result == noErr {
            self.action = action
        } else {
            unregister()
        }
        return result
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        action = nil
    }
}
