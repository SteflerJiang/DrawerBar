import AppKit

struct SpacingReloadTarget: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let pid: pid_t
    let url: URL
}

struct SpacingReloadResult {
    var reopened: [String] = []
    var failures: [String] = []
}

/// Reopening an owning app is required for its cached AppKit spacing on macOS 26.
/// Only explicitly selected apps are touched; refusing to quit is never overridden.
@MainActor
enum SpacingReloader {
    static func reopen(_ targets: [SpacingReloadTarget], progress: (String) -> Void) async -> SpacingReloadResult {
        var result = SpacingReloadResult()
        for target in targets {
            progress(target.name)
            if let running = NSRunningApplication(processIdentifier: target.pid), !running.isTerminated {
                guard running.terminate() else { result.failures.append(target.name); continue }
                for _ in 0..<60 {
                    if running.isTerminated { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                guard running.isTerminated else { result.failures.append(target.name); continue }
            }
            do {
                let options = NSWorkspace.OpenConfiguration()
                options.activates = false
                options.addsToRecentItems = false
                options.createsNewApplicationInstance = false
                options.promptsUserIfNeeded = false
                let app = try await NSWorkspace.shared.openApplication(at: target.url, configuration: options)
                guard !app.isTerminated, app.processIdentifier != target.pid else {
                    result.failures.append(target.name); continue
                }
                result.reopened.append(target.bundleID)
            } catch { result.failures.append(target.name) }
        }
        return result
    }
}
