import Carbon
import Foundation

/// A system-wide hold-to-talk shortcut (⌥ Space by default) using Carbon's
/// hot-key API: it reports both press and release and needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: () -> Void

    nonisolated(unsafe) private static var current: GlobalHotKey?

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey), onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        Self.current = self
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            let kind = GetEventKind(event)
            let pressed = kind == UInt32(kEventHotKeyPressed)
            Task { @MainActor in
                if pressed { GlobalHotKey.current?.onPress() } else { GlobalHotKey.current?.onRelease() }
            }
            return noErr
        }, 2, &types, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4E4F5641), id: 1)   // 'NOVA'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
        if Self.current === self { Self.current = nil }
    }
}
