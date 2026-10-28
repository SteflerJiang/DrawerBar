import AppKit
import MenuBarCore

@MainActor
final class NativeLayoutStore {
    static let tableKey = "TrailingItemPreferredPositions"
    static var expectedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")
    }
    private var url: URL?
    private var scoped = false
    private let bookmarkKey = "DrawerBar.NativeLayoutBookmark"
    private(set) var diagnostic: [String: Any] = [:]

    private func hostDefaults() -> UserDefaults? {
        guard let url else { return nil }
        let initializer = NSSelectorFromString("_initWithSuiteName:container:")
        guard UserDefaults.instancesRespond(to: initializer),
              let allocated = (UserDefaults.self as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        let container = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return allocated.perform(initializer, with: "com.apple.MenuBar", with: container as NSURL)?.takeRetainedValue() as? UserDefaults
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let restored = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
               restored.standardizedFileURL == Self.expectedURL.standardizedFileURL {
                scoped = restored.startAccessingSecurityScopedResource()
                url = restored
                if (try? read()) == nil { if scoped { restored.stopAccessingSecurityScopedResource() }; url = nil; scoped = false }
            }
        }
    }

    var available: Bool { url != nil }

    func requestAccess() async -> Bool {
        let panel = NSOpenPanel()
        panel.title = L("菜单栏排序文件")
        panel.message = L("请选择 com.apple.MenuBar.plist，允许小屉读取和调整图标顺序。修改前会备份，仅访问这个文件。")
        panel.prompt = L("授权排序")
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = Self.expectedURL.deletingLastPathComponent()
        let response = await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0) } }
        guard response == .OK, let chosen = panel.url,
              chosen.standardizedFileURL == Self.expectedURL.standardizedFileURL else { return false }
        if scoped { url?.stopAccessingSecurityScopedResource() }
        scoped = chosen.startAccessingSecurityScopedResource(); url = chosen
        do {
            _ = try read()
            let bookmark = try chosen.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return true
        } catch {
            if scoped { chosen.stopAccessingSecurityScopedResource() }
            url = nil; scoped = false
            return false
        }
    }

    func read() throws -> [String: Double] {
        guard let url else { throw ServiceError.nativeLayoutAccessRequired }
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let values = root[Self.tableKey] as? [String: NSNumber] else { throw ServiceError.nativeLayoutAccessRequired }
        return values.mapValues(\.doubleValue)
    }

    func apply(_ changes: [String: Double], removing: Set<String> = []) throws {
        guard !changes.isEmpty || !removing.isEmpty else { return }
        guard let url else { throw ServiceError.nativeLayoutAccessRequired }
        var current = try read()
        guard let defaults = hostDefaults() else { throw ServiceError.unsupported }
        defaults.synchronize()
        let cached = defaults.dictionary(forKey: Self.tableKey) as? [String: NSNumber]
        diagnostic = ["cached": cached?.mapValues(\.doubleValue) as Any? ?? NSNull(), "file": current,
                      "requested": changes, "route": "host-notification-and-selected-file"]
        let before = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: before, options: [], format: nil) as? [String: Any],
              let original = root[Self.tableKey] as? [String: NSNumber], original.mapValues(\.doubleValue) == current else {
            throw ServiceError.nativeLayoutConflict
        }
        let backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuBarStudio/native-layout-original.plist")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try before.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        for key in removing { current.removeValue(forKey: key) }
        for (key, value) in changes { guard value.isFinite else { throw ServiceError.nativeLayoutConflict }; current[key] = value }
        guard try Data(contentsOf: url) == before else { throw ServiceError.nativeLayoutConflict }
        let touched = Set(changes.keys).union(removing)
        guard let cached, cached.mapValues(\.doubleValue).filter({ !touched.contains($0.key) }) ==
                original.mapValues(\.doubleValue).filter({ !touched.contains($0.key) }) else {
            throw ServiceError.nativeLayoutConflict
        }
        // Use the host's suite and container so cfprefsd sends its live KVO
        // notification. An absolute-path domain writes the same disk file but
        // has a different notification identity and does not reorder the host.
        defaults.set(current, forKey: Self.tableKey)
        guard defaults.synchronize() else { throw ServiceError.nativeLayoutConflict }
        // The container suite delivers the host notification; its disk flush
        // may be deferred. Commit the same value through the authorized file
        // domain before verifying persistence, so neither cache has old data.
        let fileDomain = url.deletingPathExtension().path as CFString
        CFPreferencesSetAppValue(Self.tableKey as CFString, current as CFDictionary, fileDomain)
        guard CFPreferencesAppSynchronize(fileDomain) else { throw ServiceError.nativeLayoutConflict }
        // A single-file grant can leave the preferences service using a local
        // cache. The selected URL is the authorized persistent commit point.
        var updated = root; updated[Self.tableKey] = current
        let data = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
        diagnostic["actual"] = try read()
        guard try read() == current else { throw ServiceError.nativeLayoutConflict }
    }
}
