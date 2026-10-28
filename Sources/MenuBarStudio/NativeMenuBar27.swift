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
    private(set) var pressTrace: [[String: Any]] = []

    var available: Bool { bridge.available }

    private var entranceKey: String {
        "status:\(Bundle.main.bundleIdentifier ?? "local.menubarstudio.app")::MenuBarStudio.Entrance"
    }

    private var activeOwners: Set<String> {
        Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap { $0 } })
    }

    func ensureLeading() async throws {
        let positions = try layoutStore.read()
        guard var patch = NativeBarOrderPolicy.pinEntrance(positions: positions, entrance: entranceKey, activeOwners: activeOwners) else {
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

    private func prepareInsertion(_ entry: MenuBarEntry) throws {
        let positions = try layoutStore.read()
        var targets = positions.keys.filter { NativeBarOrderPolicy.owner(of: $0) == entry.bundleID }
        if targets.isEmpty { targets = positions.keys.filter { NativeBarOrderPolicy.owner(of: $0) == entry.name } }
        let visible = Set(entries.values.filter { $0.placement == .visible && $0.id != entry.id }.flatMap { [$0.bundleID, $0.name] })
            .union(activeOwners.filter { $0.hasPrefix("com.apple.") })
        guard let patch = NativeBarOrderPolicy.insertAfterEntrance(positions: positions, entrance: entranceKey,
            targets: targets, activeOwners: activeOwners, visibleOwners: visible) else { throw ServiceError.nativeLayoutUnmapped }
        try layoutStore.apply(patch)
    }

    func discover(frames: [(CGRect, pid_t)], existing: [MenuBarEntry], config: UserConfiguration) -> [MenuBarEntry] {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: MenuBarEntry] = [:]
        // MenuBarAgent can already draw a new item while its owner's
        // AXExtrasMenuBar still omits it. Prefer the host's actual geometry.
        let hosted = drawnItems()?.map { ($0.frame, $0.pid) } ?? []
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
        backgroundApply?.cancel()
        if target == .visible { try await ensureLeading() }
        else {
            // Hiding an overflowing icon can itself restore a leading entrance;
            // do not require an already valid layout before freeing that space.
            let positions = try layoutStore.read()
            guard let patch = NativeBarOrderPolicy.pinEntrance(positions: positions, entrance: entranceKey, activeOwners: activeOwners) else {
                throw ServiceError.nativeLayoutUnmapped
            }
            try layoutStore.apply(patch)
        }
        transitionTrace = [stage("before", target: original)]
        let beforeEntrance = entranceFrame()
        let beforeOwners = drawnOwners() ?? []
        if let beforeEntrance {
            let widths = drawnItems()?.filter { $0.pid == original.pid && abs($0.frame.midY - beforeEntrance.midY) < 4 }.map(\.frame.width) ?? []
            if !widths.isEmpty { slotWidths[original.id] = widths.reduce(0, +) }
        }
        let previous = entries[original.id] ?? original
        let previousCollapsed = wantsCollapsed
        let originalPositions = try layoutStore.read()
        var overlay: EntranceTransition?
        let wasHidden = previous.placement == .shelf && bridge.allowedBundleIDs?.contains(original.bundleID) == false
        let reservedWidth = max(18, slotWidths[original.id] ?? children(pid: original.pid).compactMap(frame).map(\.width).reduce(0, +))
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
                try prepareInsertion(original)
                if wasHidden, let entrance {
                    let height = NSScreen.screens.first?.frame.maxY ?? 0
                    let otherFrames = drawnItems()?.filter { $0.pid == getpid() }.map {
                        CGRect(x: $0.frame.minX, y: height - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
                    } ?? []
                    guard let transition = EntranceTransition(item: entrance, otherFrames: otherFrames) else { throw ServiceError.nativeLayoutUnconfirmed }
                    overlay = transition
                    _ = try await transition.reserve(width: reservedWidth)
                    transitionTrace.append(stage("space-reserved", target: original, visualEntrance: transition.frame))
                    transitionTrace[transitionTrace.count - 1]["visualEntrances"] = transition.frames.map { frame -> [String: Double] in
                        ["x": frame.minX, "y": height - frame.maxY, "width": frame.width, "height": frame.height]
                    }
                    guard drawnOwners()?.contains(original.pid) == false else { throw ServiceError.nativeLayoutUnconfirmed }
                    transition.handOffSpace()
                }
            }
            entries[original.id] = updated; wantsCollapsed = collapsed
            try await synchronize()
            // Verify actual drawn owners, not AXExtrasMenuBar's cached frames.
            let shouldBeVisible = target == .visible || !collapsed || systemUIExpanded
            var stable = 0
            var lastGeometry: [CGFloat]?
            for _ in 0..<24 {
                try await Task.sleep(nanoseconds: 40_000_000)
                let ordered: Bool
                if let own = entranceFrame() {
                    let peers = managedFrames(excluding: original.pid)
                    if shouldBeVisible, let itemFrame = currentFrame(original) {
                        ordered = NativeBarOrderPolicy.isImmediateRight(entrance: own, target: itemFrame, peers: peers)
                    } else { ordered = NativeBarOrderPolicy.isLeading(entrance: own, peers: peers) }
                } else { ordered = false }
                let own = entranceFrame()
                let item = shouldBeVisible ? currentFrame(original) : nil
                let geometry = [own?.minX ?? -99999, own?.width ?? 0, item?.minX ?? 0, item?.width ?? 0]
                let still = lastGeometry.map { zip($0, geometry).allSatisfy { abs($0 - $1) < 0.5 } } ?? false
                if let owners = drawnOwners(), owners.contains(original.pid) == shouldBeVisible, ordered {
                    stable = still ? stable + 1 : 1
                }
                else { stable = 0 }
                lastGeometry = geometry
                if stable >= 3 {
                    updated.placementVerified = true
                    if target == .visible, let frame = currentFrame(updated) { updated.frame = frame }
                    let removedOwners = beforeOwners.subtracting(drawnOwners() ?? []).intersection(Set(entries.values.map(\.pid)))
                    if target == .shelf, removedOwners == [original.pid],
                       let beforeEntrance, let after = entranceFrame(), after.minX > beforeEntrance.minX {
                        slotWidths[original.id] = after.minX - beforeEntrance.minX
                    }
                    entries[original.id] = updated
                    transitionTrace.append(stage("settled", target: updated, visualEntrance: overlay?.frame))
                    overlay?.finish()
                    return updated
                }
            }
            throw ServiceError.nativeLayoutUnconfirmed
        } catch {
            overlay?.finish()
            entries[original.id] = previous
            wantsCollapsed = previousCollapsed
            // Restore the prior allow-list as well as the saved category.
            // Releasing every hidden app would introduce unrelated icons.
            do { try await synchronize() } catch { bridge.release() }
            // Revert only this transaction's own and target weights; unrelated
            // app/system entries remain exactly as the host last wrote them.
            if let current = try? layoutStore.read() {
                let touched = Set(current.keys.filter { $0 == entranceKey || NativeBarOrderPolicy.owner(of: $0) == original.bundleID })
                try? layoutStore.apply(originalPositions.filter { touched.contains($0.key) },
                    removing: touched.subtracting(originalPositions.keys))
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
            while !queue.isEmpty && visited.count < 32 {
                let item = queue.removeFirst()
                guard !visited.contains(where: { CFEqual($0, item) }) else { continue }
                visited.append(item)
                var names: CFArray?
                let copied = AXUIElementCopyActionNames(item, &names)
                let actions = names as? [String] ?? []
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
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw right ? ServiceError.contextMenuUnavailable : ServiceError.notVisible
    }

    struct DrawnItem { let pid: pid_t; let frame: CGRect; let source: CGRect?; let element: AXUIElement }

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
                for _ in 0..<8 {
                    var pid: pid_t = 0
                    guard AXUIElementGetPid(current, &pid) == .success else { return nil }
                    if pid != agent.processIdentifier { items.append(DrawnItem(pid: pid, frame: bounds, source: frame(current), element: current)); break }
                    guard let next = (value(current, kAXChildrenAttribute) as? [AXUIElement])?.first else { break }
                    current = next
                }
            }
        }
        return count > 0 ? items : nil
    }

    func drawnOwners() -> Set<pid_t>? { drawnItems().map { Set($0.map(\.pid)) } }

    private func entranceFrame() -> CGRect? {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        guard let window = entrance?.button?.window, window.frame.height > 0 else { return nil }
        let expectedY = height - window.frame.midY
        return drawnItems()?.filter { $0.pid == getpid() && abs($0.frame.midY - expectedY) < 6 }
            .min(by: { abs($0.frame.minX - window.frame.minX) < abs($1.frame.minX - window.frame.minX) })?.frame
    }

    private func managedFrames(excluding pid: pid_t? = nil) -> [CGRect] {
        let pids = Set(entries.values.map(\.pid)).subtracting(pid.map { [$0] } ?? [])
        return drawnItems()?.filter { pids.contains($0.pid) }.map(\.frame) ?? []
    }

    private func stage(_ name: String, target: MenuBarEntry, visualEntrance: CGRect? = nil) -> [String: Any] {
        func geometry(_ frame: CGRect) -> [String: Double] { ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height] }
        var result: [String: Any] = ["phase": name, "targetDrawn": drawnOwners()?.contains(target.pid) ?? false]
        result["target"] = geometry(currentFrame(target) ?? target.frame)
        if let own = entranceFrame() { result["entrance"] = geometry(own) }
        if let visualEntrance {
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            result["visualEntrance"] = geometry(CGRect(x: visualEntrance.minX, y: height - visualEntrance.maxY,
                width: visualEntrance.width, height: visualEntrance.height))
        }
        result["peers"] = entries.values.filter { $0.pid != target.pid }.compactMap { entry -> [String: Any]? in
            guard drawnOwners()?.contains(entry.pid) == true, let rect = currentFrame(entry) else { return nil }
            return ["id": entry.id, "frame": geometry(rect)]
        }
        result["drawnItems"] = drawnItems()?.map { ["pid": Int($0.pid), "frame": geometry($0.frame)] as [String: Any] }
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
         "layoutWrite": layoutStore.diagnostic,
         "orderWeights": (try? layoutStore.read()) as Any? ?? NSNull(),
         "entranceLeading": entranceFrame().map { NativeBarOrderPolicy.isLeading(entrance: $0, peers: managedFrames()) } ?? false,
         "transitions": transitionTrace,
         "pressTrace": pressTrace,
         "restrictionActive": bridge.allowedBundleIDs != nil,
         "systemUIExpanded": systemUIExpanded,
         "drawnOwners": drawnOwners()?.map(Int.init).sorted() as Any? ?? NSNull(),
         "drawnItems": drawnItems()?.map { ["pid": Int($0.pid), "x": $0.frame.minX, "y": $0.frame.minY,
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
