import Foundation

/// Use the same resource bundle for AppKit, SwiftUI, and core model labels.
/// macOS chooses the best supported language from the user's app language list.
public enum L10n {
    public static var appName: String { text("小屉") }
    private static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MenuBarStudio_MenuBarCore.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return Bundle.module
    }()
    public static var language: String {
        Bundle.preferredLocalizations(from: ["en", "zh-Hans"],
            forPreferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages).first ?? "en"
    }

    public static func text(_ key: String, language: String? = nil) -> String {
        let bundle: Bundle
        // SwiftPM normalizes localization directory names to lowercase.
        let code = (language ?? self.language).lowercased()
        if let localized = Bundle(url: resources.bundleURL.appendingPathComponent(code + ".lproj")) {
            bundle = localized
        } else {
            bundle = resources
        }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}

public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = L10n.text(key)
    return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
}
