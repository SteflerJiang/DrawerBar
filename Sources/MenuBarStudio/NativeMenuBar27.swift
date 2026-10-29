import AppKit
import ApplicationServices
import MenuBarCore

// Runtime selector signatures were checked against macOS 27.2 and the MIT
// MenuBarHider project. See ThirdPartyNotices/MenuBarHider-LICENSE.txt.
@objc private protocol NativeMenuBarAssertion {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(configuration: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

@MainActor
final class NativeVisibilityBridge {
    private let assertionClass: NSObject.Type?
    private let configurationClass: NSObject.Type?
    private let initializer = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private var active: NativeMenuBarAssertion?
    private var pending: NativeMenuBarAssertion?
    private var completion: ((Error?) -> Void)?
    private(set) var allowedBundleIDs: Set<String>?

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW)
        let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type
        if assertion?.instancesRespond(to: #selector(NativeMenuBarAssertion.activate(configuration:completionHandler:))) == true,
           assertion?.instancesRespond(to: #selector(NativeMenuBarAssertion.invalidate)) == true,
           configuration?.instancesRespond(to: initializer) == true {
            assertionClass = assertion; configurationClass = configuration
        } else { assertionClass = nil; configurationClass = nil }
    }

    var available: Bool { assertionClass != nil && configurationClass != nil }

    func apply(_ allowed: Set<String>) async throws {
        if allowedBundleIDs == allowed, pending == nil { return }
        guard let assertionClass, let configurationClass,
              let allocated = (configurationClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let configuration = allocated.perform(initializer,
                with: (0...8).map { NSNumber(value: $0) } as NSArray,
                with: allowed.sorted() as NSArray)?.takeRetainedValue() else { throw ServiceError.unsupported }
        cancelPending()
        let assertion = unsafeBitCast(assertionClass.init(), to: NativeMenuBarAssertion.self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = assertion
            completion = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            assertion.activate(configuration: configuration) { [weak self] error in
                Task { @MainActor in self?.finish(assertion, allowed: allowed, error: error) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.finish(assertion, allowed: allowed, error: ServiceError.notMoved)
            }
        }
    }

    private func finish(_ assertion: NativeMenuBarAssertion, allowed: Set<String>, error: Error?) {
        guard pending === assertion else { return }
        let callback = completion
        pending = nil; completion = nil
        if error == nil {
            let previous = active
            active = assertion; allowedBundleIDs = allowed
            previous?.invalidate()
        } else { assertion.invalidate() }
        callback?(error)
    }

    private func cancelPending() {
        let callback = completion
        completion = nil
        pending?.invalidate(); pending = nil
        callback?(CancellationError())
    }

    func release() {
        cancelPending(); active?.invalidate(); active = nil; allowedBundleIDs = nil
    }
}

@MainActor
final class NativeMenuBar27 {
    let bridge = NativeVisibilityBridge()
    let layoutStore = NativeLayoutStore()
    weak var entrance: NSStatusItem?
    private(set) var transitionTrace: [[String: Any]] = []
    private(set) var entries: [String: MenuBarEntry] = [:]
    private(set) var wantsCollapsed = false
    private var backgroundApply: Task<Void, Never>?
    private var systemUIExpanded = false
    private var systemUIUntil = Date.distantPast
    private var slotWidths: [String: CGFloat] = [:]
    private var unrestrictedSystemWidths: [String: CGFloat] = [:]
    private var unrestrictedSystemSharingState: Bool?
    private var restrictionExtraWidths: [Bool: CGFloat] = [:]
    private var transitionStarted = Date()
    private(set) var pressTrace: [[String: Any]] = []

    var available: Bool { bridge.available }

    private func entranceKey(in positions: [String: Double]) -> String? {
        let aliases = Set([Bundle.main.executableURL?.lastPathComponent,
                           Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
                           NSRunningApplication.current.localizedName].compactMap { $0 })
        return NativeBarOrderPolicy.entranceKey(positions: positions,
            preferredOwner: Bundle.main.bundleIdentifier ?? "local.menubarstudio.app", alternateOwners: aliases)
    }

    private var activeOwners: Set<String> {
        Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap { $0 } })
    }

    private func positionsWithEntrance() throws -> [String: Double] {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { throw ServiceError.nativeInstallationRequired }
        var positions = try layoutStore.read()
        let aliases = Set([Bundle.main.executableURL?.lastPathComponent,
                           Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
                           NSRunningApplication.current.localizedName].compactMap { $0 })
        var patch = NativeBarOrderPolicy.entranceBootstrap(positions: positions,
            preferredOwner: Bundle.main.bundleIdentifier ?? "local.menubarstudio.app", alternateOwners: aliases,
            fallbackPosition: Double(NSScreen.screens.map { $0.frame.width }.max() ?? 1440) + 32)
        positions.merge(patch) { _, value in value }
        for entry in entries.values {
            let migration = NativeBarOrderPolicy.itemBootstrap(positions: positions,
                preferredOwner: entry.bundleID, alternateOwners: legacyAliases(for: entry))
            patch.merge(migration) { _, value in value }
            positions.merge(migration) { _, value in value }
        }
        if patch.isEmpty { return positions }
        try layoutStore.apply(patch)
        return try layoutStore.read()
    }

    private func legacyAliases(for entry: MenuBarEntry) -> Set<String> {
        let sameName = NSWorkspace.shared.runningApplications.filter { $0.localizedName == entry.name }
        return sameName.count == 1 ? [entry.name] : []
    }

    func ensureLeading() async throws {
        let positions = try positionsWithEntrance()
        guard let entranceKey = entranceKey(in: positions),
              var patch = NativeBarOrderPolicy.pinEntrance(positions: positions, entrance: entranceKey, activeOwners: activeOwners) else {
            throw ServiceError.nativeLayoutUnmapped
        }
        if patch.isEmpty, let own = entranceFrame(), !NativeBarOrderPolicy.isLeading(entrance: own, peers: managedFrames()) {
            patch[entranceKey] = (positions[entranceKey] ?? 0) + 32
        }
        try layoutStore.apply(patch)
        for _ in 0..<40 {
            if let own = entranceFrame(), NativeBarOrderPolicy.isLeading(entrance: own, peers: managedFrames()) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ServiceError.nativeLayoutUnconfirmed
    }

    private func insertionPatch(_ entry: MenuBarEntry) throws -> [String: Double] {
        var positions = try layoutStore.read()
        let identityPatch = NativeBarOrderPolicy.itemBootstrap(positions: positions,
            preferredOwner: entry.bundleID, alternateOwners: legacyAliases(for: entry))
        positions.merge(identityPatch) { _, current in current }
        let targets = positions.keys.filter { NativeBarOrderPolicy.owner(of: $0) == entry.bundleID }
        let visible = Set(entries.values.filter { $0.placement == .visible && $0.id != entry.id }.flatMap { [$0.bundleID, $0.name] })
            .union(activeOwners.filter { $0.hasPrefix("com.apple.") })
        guard let entranceKey = entranceKey(in: positions),
              let patch = NativeBarOrderPolicy.insertAfterEntrance(positions: positions, entrance: entranceKey,
            targets: targets, activeOwners: activeOwners, visibleOwners: visible) else { throw ServiceError.nativeLayoutUnmapped }
        return identityPatch.merging(patch) { _, ordered in ordered }
    }

    func discover(frames: [(CGRect, pid_t)], existing: [MenuBarEntry], config: UserConfiguration) -> [MenuBarEntry] {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: MenuBarEntry] = [:]
        // MenuBarAgent can already draw a new item while its owner's
        // AXExtrasMenuBar still omits it. Prefer the host's actual geometry.
        let hostSnapshot = drawnItems()
        if let hostSnapshot { rememberSystemSlots(hostSnapshot) }
        let hosted = hostSnapshot?.map { ($0.frame, $0.pid) } ?? []
        for (frame, pid) in hosted + frames where pid != getpid() {
            guard let app = byPID[pid], let bundle = app.bundleIdentifier, !bundle.hasPrefix("com.apple.") else { continue }
            let id = bundle + "#0"
            guard result[id] == nil else { continue }
            let placement = entries[id]?.placement ?? config.placement(for: id)
            result[id] = MenuBarEntry(id: id, windowID: 0, pid: pid, hostPID: pid,
                bundleID: bundle, name: app.localizedName ?? bundle, title: "", frame: frame,
                icon: app.icon, placement: placement, canMove: true,
                placementVerified: placement == .visible || (bridge.allowedBundleIDs?.contains(bundle) == false))
        }
        // A hidden item's AX scene may disappear; its last identity survives
        // only while the same application is still running.
        for old in existing where result[old.id] == nil && byPID[old.pid] != nil && old.placement == .shelf {
            result[old.id] = old
        }
        entries = result
        return LayoutPolicy.sorted(Array(result.keys), order: config.order).compactMap { result[$0] }
    }

    func setCollapsed(_ value: Bool) {
        wantsCollapsed = value
        if !value { backgroundApply?.cancel(); bridge.release(); return }
        guard !systemUIExpanded else { return }
        backgroundApply?.cancel()
        backgroundApply = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do { try await synchronize() }
            catch { if !Task.isCancelled { bridge.release() } }
        }
    }

    func prepareDiscovery() async {
        guard wantsCollapsed, !systemUIExpanded, bridge.allowedBundleIDs != nil else { return }
        // A newly launched app is absent from the previous allow-list, so the
        // host can suppress both its icon and source AX scene. Admit new apps
        // before scanning, while retaining every existing hidden application.
        // Await the host instead of repeatedly cancelling its pending update.
        backgroundApply?.cancel()
        try? await synchronize()
    }

    private func synchronize() async throws {
        guard wantsCollapsed, !systemUIExpanded else { bridge.release(); return }
        let hidden = Set(entries.values.filter { $0.placement == .shelf }.map(\.bundleID))
        guard !hidden.isEmpty else { bridge.release(); return }
        guard layoutStore.available else { throw ServiceError.nativeLayoutAccessRequired }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { throw ServiceError.nativeInstallationRequired }
        let allowed = NativeVisibilityPolicy.allowedBundles(
            running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)), hidden: hidden,
            ownBundle: Bundle.main.bundleIdentifier ?? "local.menubarstudio.app")
        try await bridge.apply(allowed)
    }

    func move(_ original: MenuBarEntry, to target: ItemPlacement, collapsed: Bool) async throws -> MenuBarEntry {
        guard available else { throw ServiceError.unsupported }
        transitionStarted = Date()
        backgroundApply?.cancel()
        let wasRestricted = bridge.allowedBundleIDs != nil
        let sharingState = hasWindowSharingSession
        var repinned = false
        if target == .visible { try await ensureLeading() }
        else {
            // Hiding an overflowing icon can itself restore a leading entrance;
            // do not require an already valid layout before freeing that space.
            let positions = try positionsWithEntrance()
            guard let entranceKey = entranceKey(in: positions),
                  let patch = NativeBarOrderPolicy.pinEntrance(positions: positions, entrance: entranceKey, activeOwners: activeOwners) else {
                throw ServiceError.nativeLayoutUnmapped
            }
            repinned = !patch.isEmpty
            try layoutStore.apply(patch)
        }
        let beforeItems = drawnItems() ?? []
        rememberSystemSlots(beforeItems)
        transitionTrace = [stage("before", target: original)]
        let beforeEntrance = entranceFrame(in: beforeItems)
        let renderedWidth = beforeItems.filter {
            $0.pid == original.pid && (beforeEntrance == nil || abs($0.frame.midY - beforeEntrance!.midY) < 4)
        }.map(\.frame.width).reduce(0, +)
        if renderedWidth > 0 { slotWidths[original.id] = renderedWidth }
        let previous = entries[original.id] ?? original
        let previousCollapsed = wantsCollapsed
        let originalPositions = try layoutStore.read()
        var overlay: EntranceTransition?
        var editedKeys = Set<String>()
        let wasHidden = previous.placement == .shelf && bridge.allowedBundleIDs?.contains(original.bundleID) == false
        let itemWidth = max(1, slotWidths[original.id] ?? original.frame.width)
        // Releasing the final restriction can also restore OS-owned modules.
        // Keep their width separate from the application's rendered slot.
        let releasesRestriction = target == .visible && !entries.values.contains { $0.id != original.id && $0.placement == .shelf }
        let currentSystemWidths = systemSlotWidths(beforeItems)
        let priorSystemWidths = unrestrictedSystemSharingState == sharingState ? unrestrictedSystemWidths : [:]
        let missingSystemWidth = priorSystemWidths.reduce(CGFloat(0)) {
            $0 + max(0, $1.value - (currentSystemWidths[$1.key] ?? 0))
        }
        // Window sharing can start after a cold launch has already restored
        // hidden icons, leaving no unrestricted sample in that mode. The
        // macOS 27 window-sharing capsule occupies 48 points on the validated
        // host. Prefer live measurements; use that footprint only for an
        // active own-window sharing session, never ordinary desktop operation.
        // Actual geometry still has to confirm the reservation before commit.
        let inferredSystemWidth = restrictionExtraWidths[sharingState] ?? (sharingState ? 48 : 0)
        let restoredSystemWidth = releasesRestriction ? max(missingSystemWidth, inferredSystemWidth) : 0
        let reservedWidth = itemWidth + restoredSystemWidth
        if target == .visible, wasHidden {
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            for own in drawnItems()?.filter({ $0.pid == getpid() }) ?? [] {
                guard let screen = NSScreen.screens.first(where: { abs(height - $0.frame.maxY - own.frame.minY) < 4 }),
                      let safe = screen.auxiliaryTopRightArea else { continue }
                if own.frame.minX - reservedWidth < safe.minX { throw ServiceError.nativeLayoutNoSpace }
            }
        }
        var updated = original; updated.placement = target
        do {
            if target == .visible {
                let patch = try insertionPatch(original)
                editedKeys = Set(patch.keys)
                if wasHidden, let entrance {
                    let height = NSScreen.screens.first?.frame.maxY ?? 0
                    let otherFrames = drawnItems()?.filter { $0.pid == getpid() }.map {
                        CGRect(x: $0.frame.minX, y: height - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
                    } ?? []
                    let primary = entranceFrame().map {
                        CGRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height)
                    }
                    guard let transition = EntranceTransition(item: entrance, primaryFrame: primary, otherFrames: otherFrames) else { throw ServiceError.nativeLayoutUnconfirmed }
                    overlay = transition
                    _ = try await transition.reserve(width: reservedWidth)
                    transitionTrace.append(stage("space-reserved", target: original, visualEntrance: transition.frame))
                    transitionTrace[transitionTrace.count - 1]["itemWidth"] = itemWidth
                    transitionTrace[transitionTrace.count - 1]["restoredSystemWidth"] = restoredSystemWidth
                    transitionTrace[transitionTrace.count - 1]["visualEntrances"] = transition.frames.map { frame -> [String: Double] in
                        ["x": frame.minX, "y": height - frame.maxY, "width": frame.width, "height": frame.height]
                    }
                    guard drawnOwners()?.contains(original.pid) == false else { throw ServiceError.nativeLayoutUnconfirmed }
                }
                // Preference notifications can repaint the native entrance.
                // Cover it before updating the host, including the first reveal
                // after startup, instead of installing the proxy afterwards.
                try layoutStore.apply(patch)
                overlay?.handOffSpace()
            }
            entries[original.id] = updated; wantsCollapsed = collapsed
            try await synchronize()
            // A single host snapshot per sample avoids mixing animation frames
            // and repeating cross-process AX queries for each geometry field.
            let shouldBeVisible = target == .visible || !collapsed || systemUIExpanded
            var stable = 0
            var lastGeometry: [CGFloat]?
            for _ in 0..<24 {
                try await Task.sleep(nanoseconds: 40_000_000)
                guard let items = drawnItems(), let own = entranceFrame(in: items) else { stable = 0; continue }
                let sameRow = items.filter { abs($0.frame.midY - own.midY) < 4 }
                let item = sameRow.filter { $0.pid == original.pid }.map(\.frame).min(by: { $0.minX < $1.minX })
                let peers = sameRow.filter { $0.pid != original.pid && $0.pid != getpid() && $0.systemID == nil }.map(\.frame)
                let ordered = shouldBeVisible
                    ? item.map { NativeBarOrderPolicy.isImmediateRight(entrance: own, target: $0, peers: peers) } ?? false
                    : NativeBarOrderPolicy.isLeading(entrance: own, peers: peers)
                let geometry = [own.minX, own.width, item?.minX ?? 0, item?.width ?? 0]
                let still = lastGeometry.map { zip($0, geometry).allSatisfy { abs($0 - $1) < 0.5 } } ?? false
                let visible = items.contains { $0.pid == original.pid }
                let overlaps = NativeVisibilityPolicy.hasOverlappingItems(items.map(\.frame))
                let visualAligned = overlay.map { abs($0.frame.minX - own.minX) <= 3 } ?? true
                stable = visible == shouldBeVisible && ordered && !overlaps && visualAligned ? (still ? stable + 1 : 1) : 0
                lastGeometry = geometry
                if stable >= 3 {
                    updated.placementVerified = true
                    if target == .shelf, !wasRestricted, !repinned, renderedWidth > 0,
                       let beforeEntrance {
                        let known = Set(entries.values.filter { $0.pid != original.pid }.map(\.pid))
                        let previousPeers = Set(beforeItems.map(\.pid)).intersection(known)
                        let currentPeers = Set(items.map(\.pid)).intersection(known)
                        if previousPeers == currentPeers, NativeBarOrderPolicy.isLeading(entrance: beforeEntrance,
                            peers: beforeItems.filter { known.contains($0.pid) }.map(\.frame)) {
                            restrictionExtraWidths[sharingState] = max(0, own.minX - beforeEntrance.minX - renderedWidth)
                        }
                    }
                    if target == .visible, let item { updated.frame = item }
                    // Cache the actual rendered slot. Entrance displacement may
                    // include a system indicator or a concurrent pin correction.
                    if item != nil { slotWidths[original.id] = sameRow.filter { $0.pid == original.pid }.map(\.frame.width).reduce(0, +) }
                    entries[original.id] = updated
                    transitionTrace.append(stage("settled", target: updated, visualEntrance: overlay?.frame))
                    await overlay?.finish()
                    return updated
                }
            }
            transitionTrace.append(stage("unconfirmed", target: updated, visualEntrance: overlay?.frame))
            throw ServiceError.nativeLayoutUnconfirmed
        } catch {
            await overlay?.finish()
            entries[original.id] = previous
            wantsCollapsed = previousCollapsed
            // Restore the prior allow-list as well as the saved category.
            // Releasing every hidden app would introduce unrelated icons.
            do { try await synchronize() } catch { bridge.release() }
            // Revert only this transaction's own and target weights; unrelated
            // app/system entries remain exactly as the host last wrote them.
            if !editedKeys.isEmpty {
                try? layoutStore.apply(originalPositions.filter { editedKeys.contains($0.key) },
                    removing: editedKeys.subtracting(originalPositions.keys))
            }
            throw error
        }
    }

    func currentFrame(_ entry: MenuBarEntry) -> CGRect? {
        let drawn = drawnItems()?.filter { $0.pid == entry.pid }.map(\.frame) ?? []
        let candidates = drawn.isEmpty ? children(pid: entry.pid).compactMap(frame) : drawn
        if let own = entranceFrame(), let sameRow = candidates.filter({ abs($0.midY - own.midY) < 4 }).min(by: { $0.minX < $1.minX }) {
            return sameRow
        }
        return candidates.min(by: { $0.minX < $1.minX })
    }

    func press(_ entry: MenuBarEntry, right: Bool) async throws -> AXError {
        let action = right ? "AXShowMenu" : kAXPressAction
        pressTrace = []
        // The source application's AXExtrasMenuBar can omit an item even
        // after MenuBarAgent has drawn it. Resolve the live hosted element too.
        for attempt in 0..<25 {
            let direct = children(pid: entry.pid)
            let hosted = drawnItems()?.filter { $0.pid == entry.pid }.map(\.element) ?? []
            var queue = direct + hosted
            var visited: [AXUIElement] = []
            var observedActions = false
            while !queue.isEmpty && visited.count < 32 {
                let item = queue.removeFirst()
                guard !visited.contains(where: { CFEqual($0, item) }) else { continue }
                visited.append(item)
                var names: CFArray?
                let copied = AXUIElementCopyActionNames(item, &names)
                let actions = names as? [String] ?? []
                if copied == .success && !actions.isEmpty { observedActions = true }
                if attempt == 0 || attempt == 24 {
                    pressTrace.append(["attempt": attempt, "actions": actions, "actionsError": copied.rawValue,
                        "role": value(item, kAXRoleAttribute) as? String ?? "",
                        "directCount": direct.count, "hostedCount": hosted.count])
                }
                if actions.contains(action) {
                    let result = AXUIElementPerformAction(item, action as CFString)
                    if result == .success { return result }
                    pressTrace.append(["attempt": attempt, "performError": result.rawValue])
                    // Menu tracking can outlive the AX reply timeout. The
                    // caller must confirm actual menu notifications before
                    // accepting an ambiguous delivery; never replay it.
                    if result == .cannotComplete { return result }
                    // A non-idempotent press must never be replayed after an
                    // ambiguous delivery error; only stale references may retry.
                    if result != .invalidUIElement && result != .actionUnsupported {
                        throw right ? ServiceError.contextMenuUnavailable : ServiceError.notVisible
                    }
                }
                queue += value(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
            // A fully resolved item with no context action will not acquire
            // AXShowMenu by waiting another second. No action was delivered,
            // so the caller can use one verified native pointer invocation.
            if right && attempt >= 1 && observedActions { throw ServiceError.contextMenuUnavailable }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw right ? ServiceError.contextMenuUnavailable : ServiceError.notVisible
    }

    struct DrawnItem { let pid: pid_t; let frame: CGRect; let source: CGRect?; let element: AXUIElement; let systemID: String? }

    private var hasWindowSharingSession: Bool {
        let selector = NSSelectorFromString("hasActiveWindowSharingSession")
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return NSApp.windows.contains { window in
            guard window.responds(to: selector), let implementation = window.method(for: selector) else { return false }
            return unsafeBitCast(implementation, to: Getter.self)(window, selector)
        }
    }

    private func systemSlotWidths(_ items: [DrawnItem]) -> [String: CGFloat] {
        guard let own = entranceFrame(in: items) else { return [:] }
        return Dictionary(items.compactMap { item -> (String, CGFloat)? in
            guard let id = item.systemID, abs(item.frame.midY - own.midY) < 4 else { return nil }
            return (id, item.frame.width)
        }, uniquingKeysWith: max)
    }

    private func rememberSystemSlots(_ items: [DrawnItem]) {
        guard bridge.allowedBundleIDs == nil else { return }
        unrestrictedSystemWidths = systemSlotWidths(items)
        unrestrictedSystemSharingState = hasWindowSharingSession
    }

    func drawnItems() -> [DrawnItem]? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased() == "com.apple.menubaragent"
        }) else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        guard let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var items: [DrawnItem] = []
        var count = 0
        for window in windows {
            for child in (value(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(80) {
                guard let bounds = frame(child), bounds.width > 0, bounds.height > 0 else { return nil }
                count += 1
                var current = child
                var foundSource = false
                var systemID: String?
                for _ in 0..<8 {
                    if let identifier = value(current, kAXIdentifierAttribute) as? String,
                       identifier.hasPrefix("com.apple.menuextra.") { systemID = identifier }
                    var pid: pid_t = 0
                    guard AXUIElementGetPid(current, &pid) == .success else { return nil }
                    if pid != agent.processIdentifier {
                        items.append(DrawnItem(pid: pid, frame: bounds, source: frame(current), element: current, systemID: systemID))
                        foundSource = true; break
                    }
                    guard let next = (value(current, kAXChildrenAttribute) as? [AXUIElement])?.first else { break }
                    current = next
                }
                if !foundSource, let identifier = value(child, kAXIdentifierAttribute) as? String,
                   identifier.hasPrefix("com.apple.menuextra.") {
                    items.append(DrawnItem(pid: agent.processIdentifier, frame: bounds, source: nil,
                                           element: child, systemID: identifier))
                }
            }
        }
        return count > 0 ? items : nil
    }

    func drawnOwners() -> Set<pid_t>? { drawnItems().map { Set($0.map(\.pid)) } }

    private func entranceFrame() -> CGRect? { entranceFrame(in: drawnItems() ?? []) }

    private func entranceFrame(in items: [DrawnItem]) -> CGRect? {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        guard let window = entrance?.button?.window, window.frame.height > 0 else { return nil }
        let expectedY = height - window.frame.midY
        return items.filter { $0.pid == getpid() && abs($0.frame.midY - expectedY) < 6 }
            .min(by: { abs($0.frame.minX - window.frame.minX) < abs($1.frame.minX - window.frame.minX) })?.frame
    }

    private func managedFrames(excluding pid: pid_t? = nil) -> [CGRect] {
        let pids = Set(entries.values.map(\.pid)).subtracting(pid.map { [$0] } ?? [])
        return drawnItems()?.filter { pids.contains($0.pid) }.map(\.frame) ?? []
    }

    private func stage(_ name: String, target: MenuBarEntry, visualEntrance: CGRect? = nil) -> [String: Any] {
        func geometry(_ frame: CGRect) -> [String: Double] { ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height] }
        let items = drawnItems() ?? []
        let own = entranceFrame(in: items)
        func rendered(_ pid: pid_t) -> CGRect? {
            items.filter { $0.pid == pid && (own == nil || abs($0.frame.midY - own!.midY) < 4) }
                .map(\.frame).min(by: { $0.minX < $1.minX })
        }
        var result: [String: Any] = ["phase": name, "targetDrawn": items.contains { $0.pid == target.pid },
                                    "elapsedMs": Date().timeIntervalSince(transitionStarted) * 1000]
        result["target"] = geometry(rendered(target.pid) ?? target.frame)
        if let own { result["entrance"] = geometry(own) }
        if let visualEntrance {
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            result["visualEntrance"] = geometry(CGRect(x: visualEntrance.minX, y: height - visualEntrance.maxY,
                width: visualEntrance.width, height: visualEntrance.height))
        }
        result["peers"] = entries.values.filter { $0.pid != target.pid }.compactMap { entry -> [String: Any]? in
            guard let rect = rendered(entry.pid) else { return nil }
            return ["id": entry.id, "frame": geometry(rect)]
        }
        result["drawnItems"] = items.map { ["pid": Int($0.pid), "frame": geometry($0.frame), "systemID": $0.systemID as Any? ?? NSNull()] as [String: Any] }
        return result
    }

    // Assessment restrictions block Notification Center. Temporarily release
    // while the pointer uses the right-hand system area or its panel is open.
    func updateSystemAccess(panelOpen: Bool) {
        let pointer = NSEvent.mouseLocation
        let atSystemArea = NSScreen.screens.contains { screen in
            pointer.x > screen.frame.maxX - 200 && pointer.x <= screen.frame.maxX
                && pointer.y > screen.frame.maxY - max(40, screen.safeAreaInsets.top)
        }
        if atSystemArea || panelOpen {
            systemUIUntil = Date().addingTimeInterval(1)
            if !systemUIExpanded { systemUIExpanded = true; backgroundApply?.cancel(); bridge.release() }
        } else if systemUIExpanded && Date() > systemUIUntil {
            systemUIExpanded = false; setCollapsed(wantsCollapsed)
        }
    }

    var snapshot: [String: Any] {
        ["backend": "MenuBarAgent", "available": available, "observed": drawnOwners() != nil,
         "layoutAccess": layoutStore.available,
         "unrestrictedSystemWidths": unrestrictedSystemWidths,
         "windowSharing": hasWindowSharingSession,
         "restrictionExtraWidth": restrictionExtraWidths[hasWindowSharingSession] as Any? ?? NSNull(),
         "layoutWrite": layoutStore.diagnostic,
         "orderWeights": (try? layoutStore.read()) as Any? ?? NSNull(),
         "entranceLeading": entranceFrame().map { NativeBarOrderPolicy.isLeading(entrance: $0, peers: managedFrames()) } ?? false,
         "transitions": transitionTrace,
         "pressTrace": pressTrace,
         "restrictionActive": bridge.allowedBundleIDs != nil,
         "systemUIExpanded": systemUIExpanded,
         "drawnOwners": drawnOwners()?.map(Int.init).sorted() as Any? ?? NSNull(),
         "drawnItems": drawnItems()?.map { ["pid": Int($0.pid), "systemID": $0.systemID as Any? ?? NSNull(), "x": $0.frame.minX, "y": $0.frame.minY,
             "width": $0.frame.width, "height": $0.frame.height,
             "sourceX": $0.source?.minX as Any? ?? NSNull(), "sourceY": $0.source?.minY as Any? ?? NSNull()] as [String: Any] } as Any? ?? NSNull(),
         "screens": NSScreen.screens.map { ["x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width,
             "height": $0.frame.height, "notch": $0.safeAreaInsets.top,
             "rightSafeX": $0.auxiliaryTopRightArea?.minX as Any? ?? NSNull()] as [String: Any] },
         "items": entries.values.map { ["id": $0.id, "placement": $0.placement.rawValue] }]
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.12)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private func children(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let raw = value(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return [] }
        return value(raw as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
