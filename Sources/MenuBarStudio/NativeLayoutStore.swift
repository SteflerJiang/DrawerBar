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
                if (try? Data(contentsOf: restored)) == nil || (try? read()) == nil { if scoped { restored.stopAccessingSecurityScopedResource() }; url = nil; scoped = false }
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
            _ = try Data(contentsOf: chosen)
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
        guard url != nil, let defaults = hostDefaults() else { throw ServiceError.nativeLayoutAccessRequired }
        defaults.synchronize()
        guard let stored = defaults.object(forKey: Self.tableKey) else { return [:] }
        guard let values = stored as? [String: NSNumber],
              values.values.allSatisfy({ $0.doubleValue.isFinite }) else { throw ServiceError.nativeLayoutUnmapped }
        // The preferences daemon is authoritative. Its disk flush can lag a
        // native Command-drag, including newly registered persistence IDs.
        return values.mapValues(\.doubleValue)
    }

    func apply(_ changes: [String: Double], removing: Set<String> = []) throws {
        guard !changes.isEmpty || !removing.isEmpty else { return }
        guard let defaults = hostDefaults() else { throw ServiceError.nativeLayoutAccessRequired }
        let original = try read()
        var updated = original
        for key in removing { updated.removeValue(forKey: key) }
        for (key, value) in changes {
            guard value.isFinite else { throw ServiceError.nativeLayoutConflict }
            updated[key] = value
        }
        diagnostic = ["cached": original, "requested": changes, "route": "live-host-preferences"]
        let backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuBarStudio/native-layout-original-table.plist")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [Self.tableKey: original], format: .binary, options: 0)
            try data.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        guard try read() == original else { throw ServiceError.nativeLayoutConflict }
        defaults.set(updated, forKey: Self.tableKey)
        guard defaults.synchronize() else { throw ServiceError.nativeLayoutConflict }
        // Do not also write an absolute-path domain or atomically replace the
        // plist: those create competing caches and overwrite live host changes.
        let actual = try read()
        diagnostic["actual"] = actual
        guard actual == updated else { throw ServiceError.nativeLayoutConflict }
    }
}
