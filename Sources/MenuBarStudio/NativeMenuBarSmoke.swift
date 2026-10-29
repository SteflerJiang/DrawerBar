import AppKit
import MenuBarCore

@MainActor
final class NativeSmokeProbe: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private var closeTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let wide = Bundle.main.bundleIdentifier?.hasSuffix(".wide") == true
        item = NSStatusBar.system.statusItem(withLength: wide ? 40 : 12)
        item?.autosaveName = "DrawerBar.NativeSmokeProbe"
        item?.button?.title = wide ? "DB 12" : "D"
        let menu = NSMenu()
        menu.addItem(withTitle: "DrawerBar smoke probe", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Ready", action: nil, keyEquivalent: "")
        menu.delegate = self; item?.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        closeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.item?.menu?.cancelTracking() }
        }
        closeTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }
    func menuDidClose(_ menu: NSMenu) { closeTimer?.invalidate(); closeTimer = nil }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeTimer?.invalidate()
        if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
        return .terminateNow
    }
}

extension AppController {
    func startNativeSmokeCheck() {
        Task { @MainActor in
            guard let flag = CommandLine.arguments.firstIndex(of: "--native-self-check"),
                  CommandLine.arguments.indices.contains(flag + 1) else { return }
            let output = CommandLine.arguments[flag + 1]
            @MainActor func report(_ status: String, _ checks: [String], error: String? = nil) {
                var value: [String: Any] = ["status": status, "checks": checks,
                    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                    "accessibility": service.hasAccessibility, "screenCapture": service.hasScreenCapture,
                    "state": service.arrangementSnapshot(entries)]
                if let error { value["error"] = error }
                if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: output), options: .atomic)
                }
            }
            guard service.usesNative27 else { report("failed", [], error: "macOS 27 backend was not selected"); return }
            if !service.nativeLayoutAccessAvailable {
                report("needs-layout-access", [])
                guard await service.requestNativeLayoutAccess() else { report("needs-layout-access", []); return }
            }
            while !service.hasAccessibility {
                report("needs-accessibility", [])
                page = .permissions
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            let savedConfig = config
            let savedData = try? Data(contentsOf: store.url)
            let probeURL = URL(fileURLWithPath: "/Applications/DrawerBarProbe.app")
            var probe: NSRunningApplication?
            var checks: [String] = []
            var failure: String?
            do {
                let options = NSWorkspace.OpenConfiguration()
                options.arguments = ["--native-probe"]; options.activates = false
                probe = try await NSWorkspace.shared.openApplication(at: probeURL, configuration: options)
                try await Task.sleep(nanoseconds: 700_000_000)
                // The workspace-launch refresh may already be in flight.
                // refresh() intentionally skips overlapping requests; wait for
                // actual discovery instead of treating that skip as a failure.
                for _ in 0..<50 {
                    if !refreshing && busyID == nil {
                        await refresh(captureArtwork: false, cause: "native-smoke-start")
                        if entries.contains(where: { $0.bundleID == "local.drawerbar.probe" }) { break }
                    }
                    try await Task.sleep(nanoseconds: 40_000_000)
                }
                guard let helper = entries.first(where: { $0.bundleID == "local.drawerbar.probe" }) else {
                    throw NSError(domain: "DrawerBarSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Probe not discovered via AXExtrasMenuBar"])
                }
                checks.append("AX discovery of dedicated probe")
                @MainActor func settle() async throws {
                    for _ in 0..<100 {
                        if busyID == nil && !refreshing { return }
                        try await Task.sleep(nanoseconds: 40_000_000)
                    }
                    throw ServiceError.notMoved
                }
                for round in 1...3 {
                    guard let current = entries.first(where: { $0.id == helper.id }) else { throw ServiceError.notVisible }
                    setPlacement(current, .shelf)
                    try await settle()
                    guard config.placement(for: helper.id) == .shelf, message == nil else { throw ServiceError.notMoved }
                    guard let drawn = service.arrangementSnapshot(entries)["drawnOwners"] as? [Int],
                          !drawn.contains(Int(helper.pid)) else { throw ServiceError.notMoved }
                    checks.append("hide \(round): MenuBarAgent drawn-owner verification")
                    if round == 1 {
                        toggleShelf()
                        for _ in 0..<100 {
                            if shelfPresented { break }
                            try await Task.sleep(nanoseconds: 40_000_000)
                        }
                        guard shelfPresented, shelfPanel?.isVisible == true,
                              entries.contains(where: { $0.id == helper.id && $0.placement == .shelf }) else { throw ServiceError.notVisible }
                        checks.append("drawer opens with hidden probe")
                        closeShelf()
                    }
                    guard let hidden = entries.first(where: { $0.id == helper.id }) else { throw ServiceError.notVisible }
                    setPlacement(hidden, .visible)
                    try await settle()
                    guard config.placement(for: helper.id) == .visible, message == nil else { throw ServiceError.notMoved }
                    checks.append("show \(round): MenuBarAgent drawn-owner verification")
                }
                guard let shown = entries.first(where: { $0.id == helper.id }) else { throw ServiceError.notVisible }
                setPlacement(shown, .shelf); try await settle()
                guard let hidden = entries.first(where: { $0.id == helper.id }), hidden.placement == .shelf else { throw ServiceError.notMoved }
                activate(hidden)
                for _ in 0..<150 {
                    if busyID == nil && !nativeActionInProgress { break }
                    try await Task.sleep(nanoseconds: 40_000_000)
                }
                guard !nativeActionInProgress, service.lastClickMechanism == "accessibility-macOS27",
                      service.lastNativeMenuObserved, entries.first(where: { $0.id == helper.id })?.placement == .shelf,
                      message == nil else { throw ServiceError.notMoved }
                checks.append("drawer action: temporary reveal, native probe menu, automatic rehide")
                service.setCollapsed(false)
                try await Task.sleep(nanoseconds: 400_000_000)
                guard let drawn = service.arrangementSnapshot(entries)["drawnOwners"] as? [Int],
                      drawn.contains(Int(helper.pid)) else { throw ServiceError.notMoved }
                checks.append("pause and assertion release")
            } catch { failure = error.localizedDescription }
            closeShelf(); busyID = nil
            service.setCollapsed(false)
            probe?.terminate()
            for _ in 0..<50 {
                if probe?.isTerminated != false { break }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            config = savedConfig
            entries.removeAll { $0.bundleID == "local.drawerbar.probe" }
            await refresh(captureArtwork: false, cause: "native-smoke-cleanup")
            config = savedConfig
            _ = persist()
            if let savedData {
                try? savedData.write(to: store.url, options: .atomic)
                if (try? Data(contentsOf: store.url)) == savedData { checks.append("original configuration restored byte for byte") }
                else { failure = "Configuration restoration did not match" }
            }
            if probe?.isTerminated == false { failure = "Probe did not terminate normally" }
            report(failure == nil ? "passed" : "failed", checks, error: failure)
        }
    }
}
