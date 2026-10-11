import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("applicationDidFinishLaunching: pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSApp.setActivationPolicy(.accessory) // no Dock icon, menu-bar only

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: "מתקן שפה")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "תקן טקסט מסומן / כל השדה  (\(HotKeyManager.shared.shortcutDescription))", action: nil, keyEquivalent: "").isEnabled = false
        let autoItem = menu.addItem(withTitle: "החלפה אוטומטית בזמן הקלדה", action: #selector(toggleAutoSwitch(_:)), keyEquivalent: "")
        autoItem.state = AutoSwitcher.shared.isEnabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "אשר הרשאת נגישות…", action: #selector(requestAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "יציאה", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item

        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Log.write("applicationDidFinishLaunching: AXIsProcessTrustedWithOptions(prompt)=\(trusted)")

        HotKeyManager.shared.register()
        AutoSwitcher.shared.start()
    }

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        AutoSwitcher.shared.isEnabled.toggle()
        sender.state = AutoSwitcher.shared.isEnabled ? .on : .off
    }

    @objc private func requestAccessibility() {
        PermissionPrompt.showAccessibilityAlert()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
