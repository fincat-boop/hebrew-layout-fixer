import Carbon.HIToolbox
import Foundation

/// Switches the active keyboard layout to match a conversion direction, so
/// typing continues in the right layout without a manual switch.
enum InputSourceManager {
    static func selectLayout(for direction: ConversionDirection) {
        // First one that is enabled on this Mac wins.
        let candidates: [String]
        switch direction {
        case .englishToHebrew:
            candidates = ["com.apple.keylayout.Hebrew", "com.apple.keylayout.Hebrew-QWERTY", "com.apple.keylayout.Hebrew-PC"]
        case .hebrewToEnglish:
            candidates = ["com.apple.keylayout.ABC", "com.apple.keylayout.US", "com.apple.keylayout.British"]
        }
        select(firstOf: candidates)
    }

    private static func select(firstOf inputSourceIDs: [String]) {
        // The TIS APIs assert they run on the main queue (enforced since macOS 26);
        // calling them from the background worker crashes with dispatch_assert_queue_fail.
        DispatchQueue.main.async {
            for inputSourceID in inputSourceIDs {
                let props: [CFString: Any] = [kTISPropertyInputSourceID: inputSourceID]
                guard let list = TISCreateInputSourceList(props as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
                      let source = list.first else { continue }
                let status = TISSelectInputSource(source)
                Log.write("InputSourceManager: selected \(inputSourceID), status=\(status)")
                return
            }
            Log.write("InputSourceManager: none of \(inputSourceIDs) is enabled")
        }
    }
}
