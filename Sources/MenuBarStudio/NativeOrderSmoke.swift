import AppKit
import MenuBarCore

extension AppController {
    func startNativeOrderCheck() {
        Task { @MainActor in
            guard let flag = CommandLine.arguments.firstIndex(of: "--native-order-check"),
                  CommandLine.arguments.indices.contains(flag + 1) else { return }
            let output = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            var checks: [String] = []
            var traces: [[String: Any]] = []
            @MainActor func report(_ status: String, error: String? = nil) {
                var value: [String: Any] = ["status": status, "checks": checks, "traces": traces,
                    "accessibility": service.hasAccessibility, "layoutAccess": service.nativeLayoutAccessAvailable,
                    "screenCapture": service.hasScreenCapture, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                    "state": service.arrangementSnapshot(entries), "message": message as Any? ?? NSNull()]
                if let error { value["error"] = error }
                if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: output, options: .atomic)
                }
            }
            if !service.nativeLayoutAccessAvailable {
                report("needs-layout-access")
                guard await service.requestNativeLayoutAccess() else { report("needs-layout-access"); return }
            }
            while !service.hasAccessibility {
                report("needs-accessibility"); page = .permissions
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            let savedConfig = config
            let savedData = try? Data(contentsOf: store.url)
            var baseline: [String: Double] = [:]
            var probes: [NSRunningApplication] = []
            let probeOwners: Set<String> = ["local.drawerbar.probe", "local.drawerbar.probe.wide"]
            var failure: String?
            @MainActor func waitIdle() async throws {
                for _ in 0..<200 {
                    if busyID == nil && !refreshing { return }
                    try await Task.sleep(nanoseconds: 40_000_000)
                }
                throw ServiceError.nativeLayoutUnconfirmed
            }
            @MainActor func assertRule(_ value: Bool, _ detail: String) throws {
                if !value { throw NSError(domain: "NativeOrderCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: detail]) }
            }
            func rect(_ value: Any?) -> CGRect? {
                guard let v = value as? [String: Double], let x = v["x"], let y = v["y"],
                      let width = v["width"], let height = v["height"] else { return nil }
                return CGRect(x: x, y: y, width: width, height: height)
            }
            func drawn(_ stage: [String: Any]) -> [(pid: Int, frame: CGRect)] {
                (stage["drawnItems"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let pid = item["pid"] as? Int, let frame = rect(item["frame"]) else { return nil }
                    return (pid, frame)
                }
            }
            do {
                try await waitIdle()
                await refresh(captureArtwork: false, cause: "order-check-baseline")
                try await waitIdle()
                baseline = try service.nativeLayoutPositions()
                for name in ["DrawerBarProbe", "DrawerBarProbeWide"] {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.arguments = ["--native-probe"]; configuration.activates = false
                    probes.append(try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/\(name).app"), configuration: configuration))
                }
                for _ in 0..<30 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    await refresh(captureArtwork: false, cause: "order-check-probes")
                    try await waitIdle()
                    if probeOwners.isSubset(of: Set(entries.map(\.bundleID))) { break }
                }
                guard let narrowID = entries.first(where: { $0.bundleID == "local.drawerbar.probe" })?.id,
                      let wideID = entries.first(where: { $0.bundleID == "local.drawerbar.probe.wide" })?.id else { throw ServiceError.notVisible }
                for round in 1...3 {
                    // Start with a real visible peer between the entrance and
                    // the item to hide, so right-packing is not tested on the
                    // entrance alone.
                    for id in [wideID, narrowID] {
                        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw ServiceError.notVisible }
                        busyID = id
                        entries[index] = try await service.move(entries[index], to: .visible, collapseAfter: true)
                        busyID = nil
                    }
                    guard let wide = entries.first(where: { $0.id == wideID }) else { throw ServiceError.notVisible }
                    setPlacement(wide, .shelf); try await waitIdle()
                    let hiddenSnapshot = service.arrangementSnapshot(entries)
                    let hide = hiddenSnapshot["transitions"] as? [[String: Any]] ?? []
                    traces.append(["operation": "hide", "round": round, "stages": hide])
                    guard let before = hide.first, let after = hide.last,
                          let oldArrow = rect(before["entrance"]), let newArrow = rect(after["entrance"]),
                          let removed = rect(before["target"]) else { throw ServiceError.nativeLayoutUnconfirmed }
                    let delta = newArrow.minX - oldArrow.minX
                    try assertRule(hiddenSnapshot["entranceLeading"] as? Bool == true, "Entrance must remain leftmost after hide")
                    try assertRule(abs(delta - removed.width) <= 3, "Hide must right-pack the entrance by the removed slot width")
                    let oldPeers = before["peers"] as? [[String: Any]] ?? []
                    let newPeers = after["peers"] as? [[String: Any]] ?? []
                    var shiftedPeer = false
                    for peer in oldPeers {
                        guard let id = peer["id"] as? String, let old = rect(peer["frame"]),
                              let replacement = newPeers.first(where: { $0["id"] as? String == id }),
                              let new = rect(replacement["frame"]) else { continue }
                        let expected = old.midX < removed.midX ? delta : 0
                        try assertRule(abs(new.minX - old.minX - expected) <= 3, "Hide must move only peers left of the removed item")
                        if id == narrowID && expected > 0 { shiftedPeer = true }
                    }
                    try assertRule(shiftedPeer, "A visible left peer must actually right-pack")
                    let oldRows = drawn(before), newRows = drawn(after)
                    let managedPIDs = Set(entries.map { Int($0.pid) })
                    var displayCount = 0
                    for own in oldRows where own.pid == Int(getpid()) {
                        guard let removed = oldRows.first(where: { $0.pid == Int(wide.pid) && abs($0.frame.midY - own.frame.midY) < 4 }),
                              let moved = newRows.first(where: { $0.pid == own.pid && abs($0.frame.midY - own.frame.midY) < 4 }) else {
                            throw ServiceError.nativeLayoutUnconfirmed
                        }
                        let shift = moved.frame.minX - own.frame.minX
                        try assertRule(abs(shift - removed.frame.width) <= 3, "Hide must right-pack on every display")
                        let peers = newRows.filter { managedPIDs.contains($0.pid) }.map(\.frame)
                        try assertRule(NativeBarOrderPolicy.isLeading(entrance: moved.frame, peers: peers), "Entrance must lead on every display")
                        for peer in oldRows where managedPIDs.contains(peer.pid) && peer.pid != Int(wide.pid) && abs(peer.frame.midY - own.frame.midY) < 4 {
                            guard let next = newRows.first(where: { $0.pid == peer.pid && abs($0.frame.midY - peer.frame.midY) < 4 }) else { continue }
                            let expected = peer.frame.midX < removed.frame.midX ? shift : 0
                            try assertRule(abs(next.frame.minX - peer.frame.minX - expected) <= 3, "Peer packing must hold on every display")
                        }
                        displayCount += 1
                    }
                    try assertRule(displayCount > 0, "No display geometry was checked")
                    checks.append("hide \(round): entrance leading, left peers right-packed, right peers unchanged on \(displayCount) displays")
                    report("running")
                    guard let hidden = entries.first(where: { $0.id == wideID }) else { throw ServiceError.notVisible }
                    setPlacement(hidden, .visible); try await waitIdle()
                    let shown = service.arrangementSnapshot(entries)
                    let show = shown["transitions"] as? [[String: Any]] ?? []
                    traces.append(["operation": "show", "round": round, "stages": show])
                    guard let reservation = show.first(where: { $0["phase"] as? String == "space-reserved" }),
                          let settled = show.last, let reservedArrow = rect(reservation["visualEntrance"]),
                          let finalArrow = rect(settled["entrance"]), let target = rect(settled["target"]) else { throw ServiceError.nativeLayoutUnconfirmed }
                    try assertRule(reservation["targetDrawn"] as? Bool == false, "Reservation must precede target visibility")
                    try assertRule(abs(reservedArrow.minX - finalArrow.minX) <= 3, "Entrance must remain in its reserved position at reveal")
                    try assertRule(target.minX >= finalArrow.maxX - 2 && target.minX <= finalArrow.maxX + 8,
                        "Shown item must be immediately right of entrance")
                    try assertRule(shown["entranceLeading"] as? Bool == true, "Entrance must remain leftmost after show")
                    let finals = drawn(settled)
                    let visualFrames = (reservation["visualEntrances"] as? [[String: Double]] ?? []).compactMap { rect($0) }
                    for own in finals where own.pid == Int(getpid()) {
                        guard let visual = visualFrames.first(where: { abs($0.midY - own.frame.midY) < 4 }) else {
                            throw NSError(domain: "NativeOrderCheck", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Missing visual reservation on display row \(own.frame.midY)"])
                        }
                        guard let incoming = finals.first(where: { $0.pid == Int(wide.pid) && abs($0.frame.midY - own.frame.midY) < 4 }) else {
                            throw NSError(domain: "NativeOrderCheck", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Missing shown target on display row \(own.frame.midY)"])
                        }
                        try assertRule(abs(visual.minX - own.frame.minX) <= 3, "Visual reservation must stay stable on every display")
                        try assertRule(incoming.frame.minX >= own.frame.maxX - 2 && incoming.frame.minX <= own.frame.maxX + 8,
                            "Shown icon must be immediately right on every display")
                    }
                    checks.append("show \(round): reserve while target hidden, stable visual entrance, adjacent insertion on \(displayCount) displays")
                    report("running")
                }
                checks.append("three rules passed with narrow and wide dedicated icons")
            } catch {
                failure = error.localizedDescription
                traces.append(["operation": "failure", "state": service.arrangementSnapshot(entries)])
            }
            closeShelf(); busyID = nil; service.setCollapsed(false)
            for probe in probes { probe.terminate() }
            for _ in 0..<60 {
                if probes.allSatisfy(\.isTerminated) { break }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            if probes.contains(where: { !$0.isTerminated }) { failure = "Test fixture did not terminate normally" }
            if !baseline.isEmpty {
                do {
                    try service.restoreNativeLayout(baseline, owners: probeOwners.union([Bundle.main.bundleIdentifier ?? "local.menubarstudio.app"]))
                    checks.append("test layout weights restored without rewriting other applications")
                } catch { failure = error.localizedDescription }
            }
            config = savedConfig; entries.removeAll { probeOwners.contains($0.bundleID) }
            await refresh(captureArtwork: false, cause: "order-check-cleanup")
            config = savedConfig; _ = persist()
            if let savedData {
                try? savedData.write(to: store.url, options: .atomic)
                if (try? Data(contentsOf: store.url)) == savedData { checks.append("original classification restored byte for byte") }
                else { failure = "Classification restoration did not match" }
            }
            report(failure == nil ? "passed" : "failed", error: failure)
        }
    }
}
