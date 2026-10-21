import AppKit
import Carbon

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let onPress: @MainActor () -> Void

    init(onPress: @escaping @MainActor () -> Void) { self.onPress = onPress }

    func register() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let install = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.onPress() }
            return noErr
        }, 1, &type, pointer, &handler)
        guard install == noErr else { return false }
        let identifier = EventHotKeyID(signature: OSType(0x534E4150), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), identifier,
                                        GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
