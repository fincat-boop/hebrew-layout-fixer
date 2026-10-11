import Cocoa
import ApplicationServices
import Carbon.HIToolbox

enum TextReplacer {

    /// Runs the full "fix selected text" flow. Must be called off the main thread
    /// since it may block briefly waiting on the pasteboard / synthetic events.
    static func fixSelectedText() {
        Log.write("fixSelectedText: start, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            Log.write("fixSelectedText: not trusted, showing alert")
            DispatchQueue.main.async { PermissionPrompt.showAccessibilityAlert() }
            return
        }

        // 1) Manual selection, via Accessibility API (fastest, no clipboard).
        if fixViaAccessibility() {
            Log.write("fixSelectedText: handled via Accessibility API (selection)")
            return
        }

        // 2) Manual selection, via a plain copy (covers apps where the AX selection
        //    lookup itself is flaky, e.g. Chromium/Electron — a real copy is a much
        //    more reliable signal that something was actually selected).
        if copyConvertPaste() {
            Log.write("fixSelectedText: handled via clipboard (selection)")
            return
        }

        // 3) Genuinely nothing selected — convert the entire field instead.
        Log.write("fixSelectedText: nothing selected anywhere — converting the entire field")
        if fixEntireFieldViaAccessibility() {
            Log.write("fixSelectedText: handled entire field via Accessibility API")
            return
        }
        Log.write("fixSelectedText: Accessibility path failed/unsupported for whole field, falling back to select-all + clipboard")
        postKeystroke(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        usleep(30_000)
        if !copyConvertPaste() {
            NSSound.beep()
        }
    }

    // MARK: - Whole-field path: used when nothing is manually selected

    private static func fixEntireFieldViaAccessibility() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusResult == .success, let element = focused else {
            Log.write("fixEntireFieldViaAccessibility: no focused element (result=\(focusResult.rawValue))")
            return false
        }
        let axElement = element as! AXUIElement

        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value)
        guard valueResult == .success, let fullText = value as? String, !fullText.isEmpty else {
            Log.write("fixEntireFieldViaAccessibility: no field value (result=\(valueResult.rawValue))")
            return false
        }
        Log.write("fixEntireFieldViaAccessibility: field has \(fullText.count) chars")

        guard let direction = LayoutMap.detectDirection(for: fullText) else {
            Log.write("fixEntireFieldViaAccessibility: no clear direction - beeping")
            NSSound.beep()
            return true // handled (nothing to do), don't fall back
        }
        let converted = LayoutMap.convert(fullText, direction: direction)

        let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, converted as CFTypeRef)
        Log.write("fixEntireFieldViaAccessibility: setResult=\(setResult.rawValue)")
        guard setResult == .success else { return false }

        // Same Chromium/Electron silent-ignore risk as the selected-text path.
        usleep(20_000)
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &verifyValue)
        if (verifyValue as? String) == fullText {
            Log.write("fixEntireFieldViaAccessibility: readback unchanged — set was silently ignored, falling back")
            return false
        }
        InputSourceManager.selectLayout(for: direction)
        return true
    }

    // MARK: - Preferred path: Accessibility API (no clipboard involved)

    private static func fixViaAccessibility() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusResult == .success, let element = focused else {
            Log.write("fixViaAccessibility: no focused element (result=\(focusResult.rawValue))")
            return false
        }
        let axElement = element as! AXUIElement

        var selectedValue: AnyObject?
        let selResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedValue)
        guard selResult == .success, let selectedText = selectedValue as? String, !selectedText.isEmpty else {
            Log.write("fixViaAccessibility: no selected text (result=\(selResult.rawValue))")
            return false
        }
        Log.write("fixViaAccessibility: selection has \(selectedText.count) chars")

        guard let direction = LayoutMap.detectDirection(for: selectedText) else {
            Log.write("fixViaAccessibility: no clear direction - beeping")
            NSSound.beep()
            return true // handled (nothing to do), don't fall back to clipboard
        }
        let converted = LayoutMap.convert(selectedText, direction: direction)

        let setResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, converted as CFTypeRef)
        Log.write("fixViaAccessibility: setResult=\(setResult.rawValue)")
        guard setResult == .success else { return false }

        // Some Chromium/Electron-based apps (web content, WhatsApp Desktop, etc.)
        // report success here but silently ignore the edit. Verify it actually
        // landed before trusting this path; otherwise fall back to clipboard.
        usleep(20_000)
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &verifyValue)
        let verifyText = verifyValue as? String
        if verifyText == selectedText {
            Log.write("fixViaAccessibility: readback still shows original text — set was silently ignored, falling back to clipboard")
            return false
        }
        InputSourceManager.selectLayout(for: direction)
        return true
    }

    // MARK: - Fallback path: simulate copy, transform, simulate paste

    /// Copies whatever is currently selected, converts it, and pastes it back.
    /// Returns false only if the copy produced no new pasteboard content at all
    /// (i.e. there was nothing selected) — the caller uses that to decide whether
    /// to fall through to a broader selection (e.g. select-all).
    @discardableResult
    private static func copyConvertPaste() -> Bool {
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        postKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        var waited = 0
        while pasteboard.changeCount == originalChangeCount && waited < 20 {
            usleep(15_000)
            waited += 1
        }

        guard pasteboard.changeCount != originalChangeCount,
              let copiedText = pasteboard.string(forType: .string),
              !copiedText.isEmpty else {
            Log.write("copyConvertPaste: copy didn't produce new pasteboard text (changeCount unchanged or empty)")
            restore(originalContents, to: pasteboard)
            return false
        }
        Log.write("copyConvertPaste: copied \(copiedText.count) chars")

        guard let direction = LayoutMap.detectDirection(for: copiedText) else {
            Log.write("copyConvertPaste: no clear direction - beeping")
            restore(originalContents, to: pasteboard)
            NSSound.beep()
            return true // something WAS selected, we just couldn't tell a direction
        }
        let converted = LayoutMap.convert(copiedText, direction: direction)
        Log.write("copyConvertPaste: pasting")

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Give the paste a moment to land before restoring the user's original clipboard.
        // Electron/Chromium apps (WhatsApp Desktop, etc.) process paste asynchronously
        // and can be slower than 200ms — restoring too early puts the ORIGINAL text
        // back on the clipboard before the app reads the converted one, so it pastes
        // stale content instead.
        usleep(600_000)
        restore(originalContents, to: pasteboard)
        InputSourceManager.selectLayout(for: direction)
        return true
    }

    private static func restore(_ contents: String?, to pasteboard: NSPasteboard) {
        guard let contents else { return }
        pasteboard.clearContents()
        pasteboard.setString(contents, forType: .string)
    }

    private static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum PermissionPrompt {
    static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "נדרשת הרשאת נגישות"
        alert.informativeText = "כדי שהתוסף יוכל להחליף את הטקסט המסומן, יש לאשר לו גישה תחת הגדרות המערכת ← פרטיות ואבטחה ← נגישות."
        alert.addButton(withTitle: "פתח הגדרות מערכת")
        alert.addButton(withTitle: "ביטול")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
