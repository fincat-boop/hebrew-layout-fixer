import Foundation

/// Minimal file logger for diagnosing issues without a debugger attached
/// (the app runs as a menu-bar agent with no visible console).
enum Log {
    static let path = NSString(string: "~/Library/Logs/HebrewLayoutFixer.log").expandingTildeInPath

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        // Keep the log small: start over once it passes 1MB.
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(atPath: path)
        }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
