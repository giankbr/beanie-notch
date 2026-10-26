import Carbon.HIToolbox

// A global shortcut (⌥Space unless changed) through Carbon's hot keys, which need no Accessibility permission.
final class HotKey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    nonisolated(unsafe) private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.action = action
        if !HotKey.handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &type, nil, nil)
            HotKey.handlerInstalled = true
        }
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x4E544359, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
