import Foundation

enum ConversionDirection {
    case englishToHebrew
    case hebrewToEnglish
}

enum LayoutMap {
    /// Standard Israeli (QWERTY-based) keyboard layout: English key -> Hebrew character it produces.
    static let englishToHebrew: [Character: Character] = [
        // Note: "w" produces the Hebrew geresh (\u{05F3} ׳), not a plain ASCII
        // apostrophe — verified against macOS's real "Hebrew" keyboard layout
        // via UCKeyTranslate, since the two look identical but are different
        // Unicode code points.
        "q": "/", "w": "\u{05F3}", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "[": "]", "]": "[",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף", "'": ",",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": "."
    ]

    static let hebrewToEnglish: [Character: Character] = {
        var reversed: [Character: Character] = [:]
        for (en, he) in englishToHebrew {
            reversed[he] = en
        }
        // Accept a plain apostrophe as an alias for the geresh, in case the
        // text came from the "Hebrew-PC" layout variant (which does use '\'').
        reversed["'"] = "w"
        return reversed
    }()

    /// Detects which direction a fix is needed for, based on the dominant script in the text.
    /// Returns nil if there isn't enough signal (e.g. only digits/punctuation, or no majority).
    static func detectDirection(for text: String) -> ConversionDirection? {
        var hebrewCount = 0
        var englishCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x05D0...0x05EA, 0x05F3, 0x05F4: // Hebrew letters, geresh, gershayim
                hebrewCount += 1
            case 0x0041...0x005A, 0x0061...0x007A: // A-Z, a-z
                englishCount += 1
            default:
                break
            }
        }
        if hebrewCount == 0 && englishCount == 0 { return nil }
        if hebrewCount > englishCount { return .hebrewToEnglish }
        if englishCount > hebrewCount { return .englishToHebrew }
        return nil
    }

    static func convert(_ text: String, direction: ConversionDirection) -> String {
        let map: [Character: Character]
        switch direction {
        case .englishToHebrew: map = englishToHebrew
        case .hebrewToEnglish: map = hebrewToEnglish
        }

        var result = String()
        result.reserveCapacity(text.count)
        for char in text {
            if direction == .englishToHebrew, char.isUppercase, let lower = char.lowercased().first, let mapped = map[lower] {
                result.append(mapped)
            } else if let mapped = map[char] {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Convenience: auto-detects direction and converts. Returns nil if direction couldn't be determined.
    static func autoConvert(_ text: String) -> String? {
        guard let direction = detectDirection(for: text) else { return nil }
        return convert(text, direction: direction)
    }
}
