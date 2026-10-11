import Cocoa
import Carbon.HIToolbox

/// Watches typing and, when the last three words were typed in the wrong layout
/// (each a real word once converted, at least two of them gibberish as typed),
/// retypes the whole run converted and switches the keyboard layout. A single
/// word is never enough on its own. Backspace right after an auto-fix reverts it.
///
/// Cost: two dictionary lookups (~0.1ms each, macOS's built-in spell checker)
/// per word, only when Space is pressed. Nothing is stored or logged except counts.
final class AutoSwitcher {
    static let shared = AutoSwitcher()

    private static let enabledKey = "autoSwitchEnabled"
    /// Marks events we post ourselves so the tap lets them through untouched.
    private static let syntheticMarker: Int64 = 0x484C_4658
    /// How many finished words back a run may reach.
    private static let maxRunWords = 8

    /// Apps where typing isn't prose (terminals, code editors) — auto mode stays off.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.apple.dt.Xcode", "com.sublimetext.4", "dev.zed.Zed", "com.exafunction.windsurf",
    ]
    private static let excludedBundlePrefixes = ["com.jetbrains."]

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    struct Fix {
        let original: [String]
        let converted: [String]
        let direction: ConversionDirection
    }

    private var tap: CFMachPort?
    private var retryTimer: Timer?
    /// The word being typed right now.
    private var buffer = ""
    /// Words finished with a single Space since the caret last jumped (click, arrows, Return…).
    private var history: [String] = []
    private var lastFix: Fix?
    /// Words the user reverted with Backspace — never auto-fixed again this session.
    private var ignored = Set<String>()

    // MARK: - Event tap lifecycle

    func start() {
        guard tap == nil else { return }
        if AXIsProcessTrusted(), installTap() { return }
        // Wait for the permission without calling tapCreate meanwhile: an event tap
        // requested while untrusted can make macOS show its permission prompt again.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            if self?.installTap() == true { timer.invalidate() }
        }
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                AutoSwitcher.shared.handle(type: type, event: event)
            },
            userInfo: nil
        ) else {
            Log.write("AutoSwitcher: tapCreate failed (permission not granted yet?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        Log.write("AutoSwitcher: event tap installed")
        return true
    }

    // MARK: - Event handling (runs on the main thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            reset()
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return pass }
        guard type == .keyDown else { reset(); return pass } // mouse click = caret moved

        guard isEnabled, !isExcludedAppFrontmost() else { reset(); return pass }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            reset()
            return pass
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            if let fix = lastFix {
                revert(fix)
                return nil
            }
            if buffer.isEmpty {
                reset() // deleting back into earlier text we no longer track exactly
            } else {
                buffer.removeLast()
            }
            return pass

        case kVK_Space:
            let word = buffer
            buffer = ""
            lastFix = nil
            guard !word.isEmpty else { reset(); return pass } // double space ends a run
            history.append(word)
            if history.count > Self.maxRunWords { history.removeFirst() }
            guard let fix = Self.fix(for: history, ignored: ignored) else { return pass }
            apply(fix)
            return nil // the swallowed Space is retyped after the converted words

        default:
            lastFix = nil
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            let typed = String(utf16CodeUnits: chars, count: length)
            // Return, Tab, arrows, Escape etc. produce control characters or nothing.
            if typed.isEmpty || typed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                reset()
            } else if buffer.count < 40 {
                buffer += typed
            }
            return pass
        }
    }

    private func reset() {
        buffer = ""
        history = []
        lastFix = nil
    }

    private func apply(_ fix: Fix) {
        // Every word but the last is followed by a single Space already in the field.
        let typedCount = fix.original.reduce(0) { $0 + $1.count } + fix.original.count - 1
        replace(charCount: typedCount, with: fix.converted.joined(separator: " ") + " ")
        InputSourceManager.selectLayout(for: fix.direction)
        history = [] // the field now holds the corrected text
        lastFix = fix
        Log.write("AutoSwitcher: auto-fixed \(fix.original.count) word(s) (\(fix.direction))")
    }

    private func revert(_ fix: Fix) {
        lastFix = nil
        ignored.formUnion(fix.original)
        let convertedCount = fix.converted.reduce(0) { $0 + $1.count } + fix.converted.count // incl. trailing Space
        replace(charCount: convertedCount, with: fix.original.joined(separator: " ") + " ")
        InputSourceManager.selectLayout(for: fix.direction == .englishToHebrew ? .hebrewToEnglish : .englishToHebrew)
        Log.write("AutoSwitcher: reverted by Backspace")
    }

    private func isExcludedAppFrontmost() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Self.excludedBundleIDs.contains(id) || Self.excludedBundlePrefixes.contains { id.hasPrefix($0) }
    }

    // MARK: - Run decision

    /// Words that must read as wrong-layout, in a row, before anything is touched.
    static let runLength = 3
    /// Of those, how many must be gibberish as typed (not merely real in both languages).
    static let minGibberish = 2

    /// Given the words finished so far (latest last), decides whether the trailing
    /// words were typed in the wrong layout and returns the run to convert.
    static func fix(for words: [String], ignored: Set<String> = []) -> Fix? {
        // Latest first; stop at the first word that can't be a wrong-layout word.
        var run: [(word: String, reading: Reading)] = []
        for word in words.reversed() {
            guard !ignored.contains(word), let r = reading(for: word), r.targetIsWord,
                  run.first.map({ $0.reading.direction == r.direction }) ?? true else { break }
            run.insert((word, r), at: 0)
        }
        let lastWords = run.suffix(runLength)
        guard lastWords.count == runLength,
              lastWords.filter({ !$0.reading.sourceIsWord }).count >= minGibberish else { return nil }

        // Earlier words join the run too, but a word that is real as typed only joins
        // if nothing came before it: in "יש deploy …" the "יש" is Hebrew, not "ha".
        if run.count < words.count {
            while run.count > runLength, let first = run.first, first.reading.sourceIsWord { run.removeFirst() }
        }
        return Fix(original: run.map(\.word), converted: run.map(\.reading.converted), direction: run[0].reading.direction)
    }

    // MARK: - Single-word reading

    struct Reading {
        let converted: String
        let direction: ConversionDirection
        /// The converted word is a real word in the other language.
        let targetIsWord: Bool
        /// The typed word is itself a real word in its own language.
        let sourceIsWord: Bool
    }

    /// Characters that are the same in both layouts and may end a word ("akuo?").
    private static let passthrough: Set<Character> = ["?", "!"]

    /// How one word reads on its own. nil = can't be a wrong-layout word at all
    /// (mixed scripts, uppercase, digits, too long).
    static func reading(for word: String) -> Reading? {
        guard word.count <= 30 else { return nil }
        let core = word.filter { !passthrough.contains($0) }
        guard !core.isEmpty else { return nil }

        let direction: ConversionDirection
        if core.allSatisfy({ LayoutMap.englishToHebrew[$0] != nil }) && core.contains(where: { $0.isASCII && $0.isLetter }) {
            direction = .englishToHebrew // also rejects uppercase (names, acronyms)
        } else if core.allSatisfy({ LayoutMap.hebrewToEnglish[$0] != nil }) && core.contains(where: isHebrewLetter) {
            direction = .hebrewToEnglish
        } else {
            return nil
        }

        let converted = LayoutMap.convert(word, direction: direction)
        let (sourceLang, targetLang) = direction == .englishToHebrew ? ("en", "he") : ("he", "en")
        // The source may shrink when trimmed: "ch," is "בית", the comma key being ת.
        let source = trimmed(word), target = trimmed(converted)
        // The Hebrew dictionary accepts almost anything with a geresh as an abbreviation.
        let geresh = direction == .englishToHebrew && target.contains("\u{05F3}")
        let targetIsWord = !target.isEmpty && !geresh && isWord(target, language: targetLang)
        let sourceIsWord = !source.isEmpty && isWord(source, language: sourceLang)
        return Reading(converted: converted, direction: direction, targetIsWord: targetIsWord, sourceIsWord: sourceIsWord)
    }

    private static func isHebrewLetter(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x05D0...0x05EA).contains($0.value) }
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.letters.inverted)
    }

    private static func isWord(_ word: String, language: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: language, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    // MARK: - Synthetic typing

    private func replace(charCount: Int, with text: String) {
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<charCount {
            post(virtualKey: CGKeyCode(kVK_Delete), text: nil, source: source)
        }
        // keyboardSetUnicodeString is capped at 20 UTF-16 units per event.
        var units = Array(text.utf16)[...]
        while !units.isEmpty {
            let chunk = Array(units.prefix(20))
            units = units.dropFirst(chunk.count)
            post(virtualKey: 0, text: chunk, source: source)
        }
    }

    private func post(virtualKey: CGKeyCode, text: [UniChar]?, source: CGEventSource?) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            if let text { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text) }
            event.post(tap: .cgSessionEventTap)
        }
    }
}
