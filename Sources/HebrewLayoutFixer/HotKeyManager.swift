import Cocoa
import Carbon.HIToolbox

/// Registers a single global keyboard shortcut (default: Cmd+Shift+H) using the
/// classic Carbon RegisterEventHotKey API, which still works for global hotkeys
/// on modern macOS even in a Swift/AppKit app.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private let signature: OSType = {
        let chars: [UInt8] = Array("HLFX".utf8)
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()

    let keyCode: UInt32 = UInt32(kVK_ANSI_H)
    let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Log.write("hotkey event received, id=\(hotKeyID.id)")
            if hotKeyID.id == 1 {
                DispatchQueue.global(qos: .userInitiated).async {
                    TextReplacer.fixSelectedText()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        Log.write("HotKeyManager.register(): InstallEventHandler=\(handlerStatus) RegisterEventHotKey=\(registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")
    }

    var shortcutDescription: String {
        "⌘⇧H"
    }
}
