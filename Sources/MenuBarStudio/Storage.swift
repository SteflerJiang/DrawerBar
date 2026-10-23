import Foundation
import MenuBarCore

final class ConfigurationStore {
    let url: URL
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuBarStudio", isDirectory: true)
        url = base.appendingPathComponent("configuration.json")
    }
    func load() -> UserConfiguration {
        guard let data = try? Data(contentsOf: url) else { return UserConfiguration() }
        guard let config = try? JSONDecoder().decode(UserConfiguration.self, from: data) else {
            // Preserve unrecognized or damaged configuration instead of replacing the only copy.
            let backup = url.deletingLastPathComponent().appendingPathComponent("configuration-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return UserConfiguration()
        }
        return config
    }
    func save(_ config: UserConfiguration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct SpacingPreferences {
    private let domain = kCFPreferencesAnyApplication
    private let user = kCFPreferencesCurrentUser
    private let host = kCFPreferencesCurrentHost
    private let spacingKey = "NSStatusItemSpacing" as CFString
    private let paddingKey = "NSStatusItemSelectionPadding" as CFString
    func read() -> SpacingSnapshot {
        SpacingSnapshot(spacing: (CFPreferencesCopyValue(spacingKey, domain, user, host) as? NSNumber)?.intValue,
                        padding: (CFPreferencesCopyValue(paddingKey, domain, user, host) as? NSNumber)?.intValue)
    }
    func write(_ snapshot: SpacingSnapshot) -> Bool {
        CFPreferencesSetValue(spacingKey, snapshot.spacing.map { NSNumber(value: $0) }, domain, user, host)
        CFPreferencesSetValue(paddingKey, snapshot.padding.map { NSNumber(value: $0) }, domain, user, host)
        return CFPreferencesSynchronize(domain, user, host) && read() == snapshot
    }
}
