import Foundation

/// Diagnostics retain application identities and geometry, never permission
/// bookmarks, credential material or arbitrary binary objects.
public enum DiagnosticsPrivacy {
    public static func sanitize(_ value: Any, home: String, depth: Int = 0) -> Any {
        guard depth < 18 else { return "<depth-limit>" }
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for key in dictionary.keys.sorted().prefix(512) {
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                guard !["bookmark", "password", "credential", "token", "serialnumber", "hardwareuuid"]
                    .contains(where: normalized.contains) else { continue }
                result[redact(key, home: home)] = sanitize(dictionary[key]!, home: home, depth: depth + 1)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.prefix(256).map { sanitize($0, home: home, depth: depth + 1) }
        }
        if let text = value as? String { return redact(String(text.prefix(8_000)), home: home) }
        if value is Data { return "<omitted-data>" }
        if let number = value as? NSNumber {
            return number.doubleValue.isFinite ? number : NSNull()
        }
        if value is NSNull { return NSNull() }
        return "<unsupported-value>"
    }

    private static func redact(_ value: String, home: String) -> String {
        var text = home.isEmpty ? value : value.replacingOccurrences(of: home, with: "~")
        text = text.replacingOccurrences(of: #"/Users/[^/\s\"\\]+"#, with: "/Users/<redacted>", options: .regularExpression)
        return text
    }
}
