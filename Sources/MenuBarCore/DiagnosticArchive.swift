import Foundation

public enum DiagnosticArchive {
    /// Read an allow-list of small app-owned logs. Never archive the support
    /// directory, UserDefaults, security-scoped bookmarks or system preferences.
    public static func write(context: Data, support: URL, destination: URL) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("DrawerBar-Diagnostics-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        let folder = temp.appendingPathComponent("DrawerBar-Diagnostics")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var report = try JSONSerialization.jsonObject(with: context) as? [String: Any] ?? [:]
        var readWarnings: [String] = []
        func read(_ name: String) -> Data? {
            let url = support.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { return nil }
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? 0) <= 4_000_000 else { readWarnings.append(name + ": skipped unsafe or oversized file"); return nil }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                return try handle.read(upToCount: 4_000_000)
            } catch { readWarnings.append(name + ": unavailable"); return nil }
        }
        for (name, key) in [("last-check.json", "lastRecordedEvent"), ("last-failure.json", "lastFailedOperation")] {
            if let data = read(name) {
                if let value = try? JSONSerialization.jsonObject(with: data) { report[key] = value }
                else { readWarnings.append(name + ": malformed JSON") }
            }
        }
        if let data = read("diagnostic-history.jsonl"), let text = String(data: data, encoding: .utf8) {
            let rows = text.split(separator: "\n").suffix(200)
            let events = rows.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            report["recentEvents"] = events
            if events.count != rows.count { readWarnings.append("history: malformed rows omitted") }
            if report["lastFailedOperation"] == nil {
                report["lastFailedOperation"] = events.last { ($0["action"] as? String) == "placement" && ($0["verified"] as? Bool) == false }
            }
        }
        report["readWarnings"] = readWarnings
        let safe = DiagnosticsPrivacy.sanitize(report, home: fm.homeDirectoryForCurrentUser.path)
        let data = try JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys])
        guard data.count <= 8_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        let reportURL = folder.appendingPathComponent("report.json")
        try data.write(to: reportURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        let readme = """
        DrawerBar diagnostics

        report.json contains OS/build/chip, display geometry (including notch),
        permission states, icon identities, bounded recent operations and the
        last failed operation, including verification and rollback details.
        No screenshots, recordings, serial numbers, permission bookmarks or
        raw system preference/configuration files are included. Home paths are redacted.
        Application names/identifiers and arrangements are included. Review before sharing.
        Nothing is uploaded automatically.
        \(L("请先复现一次显示或隐藏失败，再立即导出。发送前可检查 report.json，不会自动上传。"))
        """
        try readme.write(to: folder.appendingPathComponent("READ-ME.txt"), atomically: true, encoding: .utf8)
        let archive = temp.appendingPathComponent("diagnostics.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["--norsrc", "--noextattr", "--noqtn", "-c", "-k", "--keepParent", folder.path, archive.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
