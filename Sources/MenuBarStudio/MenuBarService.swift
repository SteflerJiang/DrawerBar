import AppKit
import ApplicationServices
import ScreenCaptureKit
import MenuBarCore
import OSLog

struct MenuBarEntry: Identifiable {
    let id: String
    var windowID: CGWindowID
    let pid: pid_t
    var hostPID: pid_t
    let bundleID: String
    let name: String
    let title: String
    var frame: CGRect
    var icon: NSImage?
    var trayImage: NSImage?
    var trayNeedsDarkBackdrop = false
    var placement: ItemPlacement
    var canMove: Bool
    var placementVerified = false
    var shelfWidth: CGFloat { max(18, trayImage?.size.width ?? frame.width) }
}

@MainActor
final class MenuBarService {
    private let native27: NativeMenuBar27? = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? NativeMenuBar27() : nil
    var usesNative27: Bool { native27 != nil }
    var divider: NSStatusItem?
    var entrance: NSStatusItem? { didSet { native27?.entrance = entrance } }
    var nativeLayoutAccessAvailable: Bool { native27?.layoutStore.available ?? true }
    func requestNativeLayoutAccess() async -> Bool { await native27?.layoutStore.requestAccess() ?? false }
    func nativeLayoutPositions() throws -> [String: Double] { try native27?.layoutStore.read() ?? [:] }
    func restoreNativeLayout(_ baseline: [String: Double], owners: Set<String>) throws {
        guard let native27 else { return }
        let current = try native27.layoutStore.read()
        let touched = Set(current.keys.filter { NativeBarOrderPolicy.owner(of: $0).map { owners.contains($0) } ?? false })
        try native27.layoutStore.apply(baseline.filter { touched.contains($0.key) }, removing: touched.subtracting(baseline.keys))
    }
    lazy var entranceImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 14, height: 12), xRadius: 2.5, yRadius: 2.5)
            body.lineWidth = 1.5; body.stroke()
            let details = NSBezierPath()
            details.lineWidth = 1.5; details.lineCapStyle = .round
            details.move(to: NSPoint(x: 2.75, y: 9)); details.line(to: NSPoint(x: 15.25, y: 9))
            for y in [6.0, 12.0] {
                details.move(to: NSPoint(x: 7, y: y)); details.line(to: NSPoint(x: 11, y: y))
            }
            details.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("小屉")
        return image
    }()
    private(set) var collapsed = false
    private var collapseInitialized = false
    private var sourceFrames: [(CGRect, pid_t)] = []
    private var statusWindowIDs: [String: CGWindowID] = [:]
    private var activeNativeMenuIDs = Set<UInt32>()
    private var activeNativeMenuPID: pid_t?
    private var nativeMenuTracking: NativeMenuTracking?
    var nativeMenuObserverAvailable: Bool { nativeMenuTracking?.available ?? false }
    private var liveWindows: [String: CGWindowID] = [:]
    private var visibleItemWindows: [String: CGWindowID] = [:]
    private var hiddenItemWindows: [String: CGWindowID] = [:]
    private(set) var lastMoveVisibilitySamples: [[String: Any]] = []
    private var activeWindowServerMove: WindowServerMoveSession?
    private let logger = Logger(subsystem: "local.menubarstudio.app", category: "MenuBar")
    private(set) var lastMoveMilliseconds: Double?
    private(set) var lastCursorDisplacement: CGFloat?
    private(set) var lastNativeMenuObserved = false
    private(set) var lastClickMechanism = ""
    private(set) var lastNativeMenuItemCount = 0
    private(set) var lastMoveTrace: [String: Double] = [:]
    var hasAccessibility: Bool { AXIsProcessTrusted() }
    var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }
    var boundaryX: CGFloat? { statusFrame(named: "MenuBarStudio.Divider", item: divider)?.minX }
    var entranceAnchor: CGRect {
        if native27 != nil, let frame = entrance?.button?.window?.frame, frame.height > 0 { return frame }
        if let frame = statusFrame(named: "MenuBarStudio.Entrance", item: entrance) {
            return cocoaRect(fromCG: frame)
        }
        // Hosted status buttons may temporarily have a placeholder window.
        // Keep the shelf on a visible screen instead of placing it below y=0.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        return CGRect(x: screen.frame.maxX - 220, y: screen.frame.maxY - height, width: 24, height: height)
    }

    private func statusFrame(named name: String, item: NSStatusItem?) -> CGRect? {
        if let id = statusWindowIDs[name],
           let value = windowInfo(id),
           let bounds = value[kCGWindowBounds as String] as? [String: Any],
           let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) { return rect }
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        if let value = windows.first(where: { ($0[kCGWindowName as String] as? String) == name }),
           let id = value[kCGWindowNumber as String] as? UInt32,
           let bounds = value[kCGWindowBounds as String] as? [String: Any],
           let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
            statusWindowIDs[name] = id
            return frame
        }
        guard let window = item?.button?.window,
              let id = LayoutPolicy.windowID(from: window.windowNumber) else { return nil }
        statusWindowIDs[name] = id
        return cgRect(fromCocoa: window.frame)
    }

    /// macOS 26 hosts third-party status windows in Control Center. Correlate
    /// each app's public accessibility extras with window geometry, not its host PID.
    func resolveHostedSources() async {
        guard hasAccessibility else { sourceFrames = []; return }
        await native27?.prepareDiscovery()
        let pids = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && !($0.bundleIdentifier?.hasPrefix("com.apple.") ?? true)
        }.map(\.processIdentifier)
        sourceFrames = await Task.detached(priority: .userInitiated) {
            var result: [(CGRect, pid_t)] = []
            func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
                var result: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
                return result
            }
            func readFrame(_ element: AXUIElement) -> CGRect? {
                guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                      let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
                var point = CGPoint.zero; var dimensions = CGSize.zero
                guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
                      AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                      dimensions.width > 0, dimensions.width < 500, dimensions.height > 0, dimensions.height < 64 else { return nil }
                return CGRect(origin: point, size: dimensions)
            }
            for pid in pids {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.18)
                guard let raw = value(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
                let bar = raw as! AXUIElement
                AXUIElementSetMessagingTimeout(bar, 0.12)
                let children = value(bar, kAXChildrenAttribute) as? [AXUIElement] ?? []
                for child in children.prefix(40) {
                    AXUIElementSetMessagingTimeout(child, 0.12)
                    if let frame = readFrame(child), !result.contains(where: { $0.1 == pid && $0.0 == frame }) {
                        result.append((frame, pid))
                    }
                }
            }
            return result
        }.value
    }

    var controlMetadataAvailable: Bool {
        if let native27 { return native27.available }
        guard let arrow = statusFrame(named: "MenuBarStudio.Entrance", item: entrance),
              let edge = statusFrame(named: "MenuBarStudio.Divider", item: divider) else { return false }
        return arrow.width > 0 && arrow.height > 0 && edge.width > 0 && edge.height > 0
    }

    func setCollapsed(_ requested: Bool) {
        if let native27 {
            native27.setCollapsed(requested)
            collapsed = requested; collapseInitialized = true
            return
        }
        // Keep icons reachable if the OS withholds the hosted control windows.
        let value = requested && controlMetadataAvailable
        guard !collapseInitialized || value != collapsed else { return }
        collapseInitialized = true
        collapsed = value
        divider?.length = value ? 10_000 : 1
    }

    func discover(existing: [MenuBarEntry] = [], config: UserConfiguration) -> [MenuBarEntry] {
        if let native27 { return native27.discover(frames: sourceFrames, existing: existing, config: config) }
        statusWindowIDs = [:]
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [String: Int] = [:]
        var usedSourceIndices = Set<Int>()
        let known = Dictionary(existing.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = info.compactMap { value -> (CGWindowID, pid_t, CGRect, String, Bool)? in
            guard let layer = value[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let number = value[kCGWindowNumber as String] as? UInt32,
                  let pid = value[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let dict = value[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary), rect.height > 0, rect.height <= 64,
                  rect.width > 0, rect.width < 1000,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
            let onScreen = value[kCGWindowIsOnscreen as String] as? Bool == true
            if !onScreen && !collapsed { return nil }
            return (number, pid, rect, value[kCGWindowName as String] as? String ?? "", onScreen)
        }.sorted { $0.2.minX == $1.2.minX ? $0.0 > $1.0 : $0.2.minX < $1.2.minX }
        var result: [MenuBarEntry] = []
        let ownWindows = Set([entrance?.button?.window?.windowNumber, divider?.button?.window?.windowNumber].compactMap { $0 }.compactMap { LayoutPolicy.windowID(from: $0) })
        for (window, hostPID, rect, title, onScreen) in windows {
            if ownWindows.contains(window) { continue }
            if title.hasPrefix("MenuBarStudio.") { continue }
            guard LayoutPolicy.participatesInStatusOrdering(windowName: title,
                hostBundleID: NSRunningApplication(processIdentifier: hostPID)?.bundleIdentifier ?? "") else { continue }
            // Live speed/battery text can shift neighboring windows between the
            // AX sample and WindowServer sample. Choose the nearest safe match.
            let tolerance = max(6, min(12, rect.width * 0.4))
            let match = sourceFrames.enumerated().filter { index, candidate in
                !usedSourceIndices.contains(index) && abs(candidate.0.midX - rect.midX) < tolerance && abs(candidate.0.midY - rect.midY) < 3
            }.min { abs($0.element.0.midX - rect.midX) < abs($1.element.0.midX - rect.midX) }
            let previous = known[window]
            guard onScreen || previous != nil || match != nil else { continue }
            let cachedPID = previous.flatMap { old -> pid_t? in
                guard old.canMove, NSRunningApplication(processIdentifier: old.pid)?.isTerminated == false else { return nil }
                return old.pid
            }
            if let match { usedSourceIndices.insert(match.offset) }
            else if let cachedPID, sourceFrames.contains(where: { $0.1 == cachedPID }) { continue }
            let pid = match?.element.1 ?? cachedPID ?? hostPID
            if pid == getpid() { continue }
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            let bundle = app.bundleIdentifier ?? "pid-\(pid)"
            // Without identity data, eleven identical Control Center rows would
            // misrepresent hosted applications. Show the permission/empty state instead.
            if bundle == "com.apple.controlcenter", title.isEmpty { continue }
            let ordinal = counts[bundle, default: 0]; counts[bundle] = ordinal + 1
            let id = LayoutPolicy.itemID(bundle: bundle, ordinal: ordinal, previousID: previous?.id)
            let isSystem = bundle.hasPrefix("com.apple.")
            let observed = statusFrame(named: "MenuBarStudio.Divider", item: divider).flatMap {
                LayoutPolicy.observedPlacement(item: rect, divider: $0)
            }
            let placement = observed ?? previous?.placement ?? config.placement(for: id)
            result.append(MenuBarEntry(id: id, windowID: window, pid: pid, hostPID: hostPID, bundleID: bundle,
                name: bundle == "com.apple.controlcenter" ? title : (app.localizedName ?? L("菜单栏项目")), title: title, frame: rect,
                icon: app.icon, trayImage: previous?.trayImage,
                trayNeedsDarkBackdrop: previous?.trayNeedsDarkBackdrop ?? false,
                placement: placement, canMove: !isSystem, placementVerified: observed != nil))
        }
        // A hidden window can disappear from the list. Keep it while its owner still runs.
        for old in existing where collapsed && old.placement == .shelf && !result.contains(where: { $0.windowID == old.windowID || $0.id == old.id }) {
            if NSRunningApplication(processIdentifier: old.pid)?.isTerminated == false { result.append(old) }
        }
        let ordered = LayoutPolicy.sorted(result.map(\.id), order: config.order)
        let map = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        visibleItemWindows = Dictionary(result.filter { $0.canMove && $0.placement == .visible }
            .map { ($0.id, $0.windowID) }, uniquingKeysWith: { first, _ in first })
        hiddenItemWindows = Dictionary(result.filter { $0.canMove && $0.placement == .shelf }
            .map { ($0.id, $0.windowID) }, uniquingKeysWith: { first, _ in first })
        return ordered.compactMap { map[$0] }
    }

    /// A cheap topology check. Dynamic traffic text changing width on the same side
    /// does not trigger another AX scan or image capture.
    func layoutSignature() -> String? {
        if native27 != nil { return nil }
        guard let values = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let edge = statusFrame(named: "MenuBarStudio.Divider", item: divider) else { return nil }
        var observed: [UInt32: ItemPlacement] = [:]
        for value in values {
            guard value[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  value[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                  let id = value[kCGWindowNumber as String] as? UInt32,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.height > 0, frame.height < 64, frame.width > 0, frame.width < 1000 else { continue }
            let name = value[kCGWindowName as String] as? String ?? ""
            guard !name.hasPrefix("MenuBarStudio.") else { continue }
            if name == "AudioVideoModule",
               let pid = value[kCGWindowOwnerPID as String] as? Int32,
               !LayoutPolicy.participatesInStatusOrdering(windowName: name,
                   hostBundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "") { continue }
            if let side = LayoutPolicy.observedPlacement(item: frame, divider: edge) { observed[id] = side }
        }
        let sides = LayoutPolicy.statusTopologySignature(observed: observed, hiddenWindows: Set(hiddenItemWindows.values))
        // Side-of-divider alone misses an app moving through the system group.
        // Record order violations, not changing traffic-meter widths.
        return sides + "|protected:" + visibleItemsCrossingProtectedBoundary().sorted().joined(separator: ",")
    }

    private func placementObservation(_ entry: MenuBarEntry) -> (frame: CGRect, divider: CGRect, entrance: CGRect, firstVisible: Bool)? {
        guard let values = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let window = values.first(where: { $0[kCGWindowNumber as String] as? UInt32 == (liveWindows[entry.id] ?? entry.windowID) }),
              let divider = values.first(where: { $0[kCGWindowName as String] as? String == "MenuBarStudio.Divider" }),
              let entrance = values.first(where: { $0[kCGWindowName as String] as? String == "MenuBarStudio.Entrance" }),
              let itemBounds = window[kCGWindowBounds as String] as? [String: Any],
              let dividerBounds = divider[kCGWindowBounds as String] as? [String: Any],
              let entranceBounds = entrance[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: itemBounds as CFDictionary),
              let edge = CGRect(dictionaryRepresentation: dividerBounds as CFDictionary),
              let arrow = CGRect(dictionaryRepresentation: entranceBounds as CFDictionary) else { return nil }
        let firstVisible = !values.contains { value in
            guard value[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let other = CGRect(dictionaryRepresentation: bounds as CFDictionary), other.width < 1000,
                  abs(other.midY - arrow.midY) < 4 else { return false }
            return other.midX > arrow.midX + 2 && other.midX < frame.midX - 2
        }
        return (frame, edge, arrow, firstVisible)
    }

    func verifiedPlacement(_ original: MenuBarEntry, target: ItemPlacement) async throws -> MenuBarEntry {
        var item = original
        var stable = 0
        for attempt in 0..<16 {
            try await Task.sleep(nanoseconds: 10_000_000)
            // Reuse the source we just resolved. Rebind only if the fast geometry
            // samples do not settle, rather than starting every check with AX work.
            if attempt >= 3, attempt % 4 == 3, let rebound = try? await revealedEntry(item) { item = rebound }
            guard let observation = placementObservation(item) else { stable = 0; continue }
            let correctSlot = target == .shelf || (observation.frame.midX > observation.entrance.midX + 2 && observation.firstVisible)
            if correctSlot && LayoutPolicy.observedPlacement(item: observation.frame, divider: observation.divider) == target {
                stable += 1
                if stable >= 2 {
                    item.frame = observation.frame; item.placement = target; item.placementVerified = true
                    return item
                }
            } else { stable = 0 }
        }
        throw ServiceError.notMoved
    }

    func capture(_ entries: [MenuBarEntry], force: Bool = false) async -> [CGWindowID: NSImage] {
        if native27 != nil { return [:] }
        guard hasScreenCapture else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            var images: [CGWindowID: NSImage] = [:]
            for entry in entries.filter({ $0.canMove && (force || $0.trayImage == nil) }).prefix(30) {
                guard let window = content.windows.first(where: { $0.windowID == entry.windowID }), window.frame.width < 1000 else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let options = SCStreamConfiguration()
                options.width = max(1, Int(window.frame.width * 2))
                options.height = max(1, Int(window.frame.height * 2))
                options.showsCursor = false
                options.ignoreShadowsSingleWindow = true
                options.captureResolution = .best
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: options) {
                    let artwork = NSImage(cgImage: image, size: window.frame.size)
                    if artworkAnalysis(artwork).hasContent { images[entry.windowID] = artwork }
                }
            }
            return images
        } catch { return [:] }
    }

    func needsDarkBackdrop(_ image: NSImage) -> Bool {
        artworkAnalysis(image).darkBackdrop
    }

    private func artworkAnalysis(_ image: NSImage) -> (hasContent: Bool, darkBackdrop: Bool) {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return (false, false) }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (false, false) }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
            var count = 0, low = 1.0, high = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 32 {
                red += Double(pixels[i]); green += Double(pixels[i + 1]); blue += Double(pixels[i + 2]); alpha += Double(pixels[i + 3])
                count += 1
                let luminance = (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / Double(pixels[i + 3])
                low = min(low, luminance); high = max(high, luminance)
            }
            guard alpha > 0, count >= 5 else { return (false, false) }
            // Offscreen captures may be transparent or a solid empty rectangle.
            let hasContent = Double(count) / Double(width * height) < 0.94 || high - low > 0.04
            return (hasContent, LayoutPolicy.prefersDarkIconBackdrop(red: red / alpha, green: green / alpha, blue: blue / alpha))
        }
    }

    func currentFrame(for entry: MenuBarEntry) -> CGRect? {
        if let native27 { return native27.currentFrame(entry) }
        guard let value = windowInfo(liveWindows[entry.id] ?? entry.windowID),
              let dict = value[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    /// Hosted windows may be replaced when the hidden region is revealed.
    /// Resolve the original app's AX item to its current on-screen host window.
    private func revealedEntry(_ original: MenuBarEntry) async throws -> MenuBarEntry {
        let app = AXUIElementCreateApplication(original.pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        func value(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(item, key as CFString, &result) == .success ? result : nil
        }
        for _ in 0..<30 {
            guard let divider = statusFrame(named: "MenuBarStudio.Divider", item: divider), divider.width < 80 else {
                try await Task.sleep(nanoseconds: 8_000_000); continue
            }
            if let bar = value(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID(),
               let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] {
                var frames: [CGRect] = []
                for child in children.prefix(20) {
                    AXUIElementSetMessagingTimeout(child, 0.08)
                    guard let pos = value(child, kAXPositionAttribute), CFGetTypeID(pos) == AXValueGetTypeID(),
                          let size = value(child, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
                    var point = CGPoint.zero, dimensions = CGSize.zero
                    guard AXValueGetValue(pos as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                          dimensions.width > 0, dimensions.height > 0 else { continue }
                    let frame = CGRect(origin: point, size: dimensions)
                    if !frames.contains(frame) { frames.append(frame) }
                }
                let ordinal = Int(original.id.split(separator: "#").last ?? "0") ?? 0
                if let target = frames.sorted(by: { $0.minX < $1.minX }).dropFirst(ordinal).first {
                    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                    let candidates = windows.compactMap { info -> (CGWindowID, pid_t, CGRect)? in
                        guard let layer = info[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.statusWindow)),
                              let id = info[kCGWindowNumber as String] as? UInt32,
                              let pid = info[kCGWindowOwnerPID as String] as? Int32,
                              let bounds = info[kCGWindowBounds as String] as? [String: Any],
                              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                              abs(rect.midX - target.midX) < 10, abs(rect.midY - target.midY) < 3 else { return nil }
                        return (id, pid, rect)
                    }
                    if let found = candidates.min(by: { abs($0.2.midX - target.midX) < abs($1.2.midX - target.midX) }) {
                        var entry = original; entry.windowID = found.0; entry.hostPID = found.1; entry.frame = found.2
                        liveWindows[entry.id] = found.0
                        if visibleItemWindows[entry.id] != nil { visibleItemWindows[entry.id] = found.0 }
                        return entry
                    }
                }
            }
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        throw ServiceError.notVisible
    }

    private func windowInfo(_ id: CGWindowID) -> [String: Any]? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first {
            ($0[kCGWindowNumber as String] as? UInt32) == id
        }
    }

    private func cgRect(fromCocoa rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func cocoaRect(fromCG rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func pointIsReachable(_ point: CGPoint) -> Bool {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        let cocoa = CGPoint(x: point.x, y: height - point.y)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoa) }) else { return false }
        guard screen.safeAreaInsets.top > 0 else { return true }
        if let left = screen.auxiliaryTopLeftArea, left.contains(cocoa) { return true }
        if let right = screen.auxiliaryTopRightArea, right.contains(cocoa) { return true }
        return false
    }

    private struct StatusWindow {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
        let name: String
    }

    private func visibleStatusWindows() -> [StatusWindow] {
        let values = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return statusWindows(values)
    }

    private func statusWindows(_ values: [[String: Any]]) -> [StatusWindow] {
        values.compactMap { value in
            guard value[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = value[kCGWindowNumber as String] as? UInt32,
                  let pid = value[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0, frame.height > 0, frame.height < 64 else { return nil }
            return StatusWindow(id: id, pid: pid, frame: frame, name: value[kCGWindowName as String] as? String ?? "")
        }
    }

    /// Unknown windows are read-only anchors too. Control Center hosts both
    /// native and third-party items, so its PID cannot identify a system item.
    private func visibleZoneWindows(_ windows: [StatusWindow]) -> [StatusWindow] {
        guard let arrow = windows.first(where: { $0.name == "MenuBarStudio.Entrance" }) else { return [] }
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        let arrowPoint = CGPoint(x: arrow.frame.midX, y: height - arrow.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(arrowPoint) }) else { return [] }
        let hidden = Set(hiddenItemWindows.values)
        return windows.filter {
            !$0.name.hasPrefix("MenuBarStudio.") && !hidden.contains($0.id)
                && ($0.name != "AudioVideoModule" || LayoutPolicy.participatesInStatusOrdering(windowName: $0.name,
                    hostBundleID: NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier ?? ""))
                && $0.frame.width < 1000 && abs($0.frame.midY - arrow.frame.midY) < 4
                && screen.frame.contains(CGPoint(x: $0.frame.midX, y: height - $0.frame.midY))
        }
    }

    func visibleItemsCrossingProtectedBoundary() -> [String] {
        if native27 != nil { return [] }
        let zone = visibleZoneWindows(visibleStatusWindows())
        let managed = Set(visibleItemWindows.values)
        let protected = zone.filter { !managed.contains($0.id) }.map(\.frame)
        return visibleItemWindows.compactMap { id, window in
            guard let item = zone.first(where: { $0.id == window }),
                  LayoutPolicy.crossesProtectedItems(item: item.frame, protectedItems: protected) else { return nil }
            return id
        }
    }

    private func leadingControls(_ windows: [StatusWindow]) -> Bool {
        guard let arrow = windows.first(where: { $0.name == "MenuBarStudio.Entrance" }),
              let edge = windows.first(where: { $0.name == "MenuBarStudio.Divider" }) else { return false }
        return LayoutPolicy.entranceIsLeading(divider: edge.frame, entrance: arrow.frame,
            otherItems: visibleZoneWindows(windows).map(\.frame))
    }

    private func firstVisibleControl(_ windows: [StatusWindow]) -> Bool {
        guard let arrow = windows.first(where: { $0.name == "MenuBarStudio.Entrance" }) else { return false }
        let items = visibleZoneWindows(windows)
        guard Set(items.map(\.id)).isSuperset(of: visibleItemWindows.values) else { return false }
        return !items.contains { $0.frame.midX < arrow.frame.midX - 2 }
    }

    /// Repair only a genuinely displaced entry, using the same directed event
    /// route as classification. Never expand the hidden region or sweep a cursor.
    func ensureLeadingEntrance() async throws {
        guard hasAccessibility else { return }
        if let native27 {
            guard native27.available else { throw ServiceError.windowMetadataUnavailable }
            try await native27.ensureLeading()
            return
        }
        guard controlMetadataAvailable else { throw ServiceError.windowMetadataUnavailable }
        let windows = visibleStatusWindows()
        if collapsed ? firstVisibleControl(windows) : leadingControls(windows) { return }
        guard let arrow = windows.first(where: { $0.name == "MenuBarStudio.Entrance" }) else { throw ServiceError.notVisible }
        guard let first = visibleZoneWindows(windows).filter({ $0.frame.midX < arrow.frame.midX - 2 })
            .min(by: { $0.frame.minX < $1.frame.minX }) else { throw ServiceError.notVisible }
        let entry = MenuBarEntry(id: "xiaoti-entrance", windowID: arrow.id, pid: getpid(), hostPID: arrow.pid,
            bundleID: "local.menubarstudio.app", name: L("小屉入口"), title: arrow.name,
            frame: arrow.frame, placement: .visible, canMove: true)
        guard let source = CGEventSource(stateID: .hidSystemState) else { throw ServiceError.notMoved }
        source.localEventsSuppressionInterval = 0
        guard let down = addressedEvent(entry, type: .leftMouseDown,
                  point: CGPoint(x: arrow.frame.midX, y: arrow.frame.midY), right: false, source: source),
              let up = addressedEvent(entry, type: .leftMouseUp,
                  point: CGPoint(x: first.frame.minX - 1, y: first.frame.midY), right: false, source: source) else { throw ServiceError.notMoved }
        down.flags = .maskCommand; up.flags = []
        for event in [down, up] { event.setIntegerValueField(.mouseEventClickState, value: 0) }
        address(up, window: first.id, pid: arrow.pid)
        try await StatusEventDelivery.send(down, to: arrow.pid)
        try? await Task.sleep(nanoseconds: 8_000_000)
        try await StatusEventDelivery.send(up, to: arrow.pid)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            let updated = visibleStatusWindows()
            if collapsed ? firstVisibleControl(updated) : leadingControls(updated) { return }
        }
        throw ServiceError.notMoved
    }

    private func settleControls(collapsed target: Bool) async {
        var stable = 0
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 12_000_000)
            let windows = visibleStatusWindows()
            guard windows.contains(where: { $0.name == "MenuBarStudio.Entrance" }) else { stable = 0; continue }
            if target {
                if let edge = windows.first(where: { $0.name == "MenuBarStudio.Divider" }), edge.frame.width < 80 {
                    stable = 0; continue
                }
                guard firstVisibleControl(windows) else { stable = 0; continue }
            } else {
                guard let edge = windows.first(where: { $0.name == "MenuBarStudio.Divider" }),
                      edge.frame.width < 80, leadingControls(windows) else { stable = 0; continue }
            }
            // Traffic meters can keep changing width while a placement is valid.
            // Wait for the required layout, not for the entire bar to stop moving.
            stable += 1
            if stable >= 2 { lastMoveTrace["controlsSettled"] = 1; return }
        }
        lastMoveTrace["controlsSettled"] = 0
    }

    func arrangementSnapshot(_ entries: [MenuBarEntry]) -> [String: Any] {
        if let native27 { return native27.snapshot }
        let windows = visibleStatusWindows()
        guard let arrow = windows.first(where: { $0.name == "MenuBarStudio.Entrance" }) else { return ["observed": false] }
        let edge = windows.first(where: { $0.name == "MenuBarStudio.Divider" })
        func geometry(_ frame: CGRect) -> [String: Double] {
            ["x": frame.minX, "width": frame.width, "midX": frame.midX]
        }
        let visibleIDs = Set(entries.filter { $0.canMove && $0.placement == .visible }.map { liveWindows[$0.id] ?? $0.windowID })
        let right = windows.filter { visibleIDs.contains($0.id)
            && abs($0.frame.midY - arrow.frame.midY) < 4 && $0.frame.midX > arrow.frame.midX + 2 }
            .sorted { $0.frame.midX < $1.frame.midX }
        return ["observed": true, "entranceLeading": collapsed ? firstVisibleControl(windows) : leadingControls(windows),
                "entrance": geometry(arrow.frame), "divider": edge.map { geometry($0.frame) } ?? [:],
                "dividerObserved": edge != nil,
                "scope": "managed-application-items",
                "protectedOrderViolations": visibleItemsCrossingProtectedBoundary(),
                "protectedWindows": visibleZoneWindows(windows).filter { !visibleIDs.contains($0.id) }
                    .map { ["window": Int($0.id), "frame": geometry($0.frame)] as [String: Any] },
                "firstRightWindow": right.first.map { Int($0.id) } ?? -1,
                "items": entries.filter(\.canMove).map { entry -> [String: Any] in
                    let id = liveWindows[entry.id] ?? entry.windowID
                    var item: [String: Any] = ["id": entry.id, "window": Int(id), "placement": entry.placement.rawValue]
                    if let window = windows.first(where: { $0.id == id }) {
                        item["observed"] = true; item["frame"] = geometry(window.frame)
                    } else { item["observed"] = false }
                    return item
                }]
    }

    func discoveryDiagnostics() -> [String: Any] {
        let values = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return ["sourceFrameCount": sourceFrames.count,
                "statusLayer": Int(CGWindowLevelForKey(.statusWindow)),
                "ownEntranceWindow": entrance?.button?.window?.windowNumber ?? -1,
                "ownDividerWindow": divider?.button?.window?.windowNumber ?? -1,
                "screenCaptureAllowed": hasScreenCapture,
                "controlMetadataAvailable": controlMetadataAvailable,
                "statusWindowCount": statusWindows(values).count]
    }

    func updateNativeSystemAccess() {
        native27?.updateSystemAccess(panelOpen: nativeMenuOpen())
    }

    private func knownReadyEntry(_ original: MenuBarEntry) async -> MenuBarEntry? {
        let id = liveWindows[original.id] ?? original.windowID
        for _ in 0..<10 {
            guard let info = windowInfo(id),
                  info[kCGWindowOwnerPID as String] as? Int32 == original.hostPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let arrow = statusFrame(named: "MenuBarStudio.Entrance", item: entrance) else { return nil }
            let correctSide: Bool
            if original.placement == .visible {
                correctSide = frame.midX > arrow.midX + 2
            } else if let edge = statusFrame(named: "MenuBarStudio.Divider", item: divider), edge.width < 80 {
                correctSide = LayoutPolicy.observedPlacement(item: frame, divider: edge) == .shelf
            } else { correctSide = false }
            if correctSide, info[kCGWindowIsOnscreen as String] as? Bool == true,
               abs(frame.midY - arrow.midY) < 4, pointIsReachable(CGPoint(x: frame.midX, y: frame.midY)) {
                var entry = original; entry.windowID = id; entry.frame = frame
                return entry
            }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        return nil
    }

    @discardableResult
    func move(_ original: MenuBarEntry, to placement: ItemPlacement, collapseAfter: Bool? = nil,
              conservative: Bool = false) async throws -> MenuBarEntry {
        guard hasAccessibility else { throw ServiceError.permission }
        guard original.canMove else { throw ServiceError.unsupported }
        if let native27 {
            let started = Date()
            defer { lastMoveMilliseconds = Date().timeIntervalSince(started) * 1000 }
            lastMoveTrace = ["menuBarAgent": 1]; lastMoveVisibilitySamples = []; lastCursorDisplacement = 0
            return try await native27.move(original, to: placement, collapsed: collapseAfter ?? collapsed)
        }
        if StatusEventDelivery.usesWindowServerRoute(to: original.hostPID) {
            return try await moveHosted(original, to: placement, collapseAfter: collapseAfter)
        }
        let started = Date()
        lastMoveTrace = ["directed": 1, "regionExpansions": 0]
        lastMoveMilliseconds = nil
        lastCursorDisplacement = nil
        lastMoveVisibilitySamples = []
        let remainedCollapsed = collapsed
        let peers = Set(hiddenItemWindows.filter { $0.key != original.id }.map(\.value))
        let visibility = MoveVisibilityProbe(peers: peers,
            checkDivider: remainedCollapsed && (collapseAfter != false || !peers.isEmpty))
        visibility.sample()
        let cursor = CGEvent(source: nil)?.location
        let hidCursor = CGDisplayHideCursor(CGMainDisplayID()) == .success
        defer {
            visibility.sample()
            lastMoveVisibilitySamples = visibility.finish()
            lastMoveTrace["visibilitySamples"] = Double(lastMoveVisibilitySamples.count)
            lastMoveTrace["peerExposureSamples"] = Double(lastMoveVisibilitySamples.filter { !($0["exposedPeers"] as? [Int] ?? []).isEmpty }.count)
            lastMoveTrace["regionExpansions"] = Double(lastMoveVisibilitySamples.filter { $0["expandedDivider"] as? Bool == true }.count)
            lastMoveMilliseconds = Date().timeIntervalSince(started) * 1000
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            if hidCursor { CGDisplayShowCursor(CGMainDisplayID()) }
            if let cursor, let after = CGEvent(source: nil)?.location {
                lastCursorDisplacement = hypot(after.x - cursor.x, after.y - cursor.y)
            }
        }
        // A failed directed move must never fall back to revealing every item.
        var entry = original
        entry.windowID = liveWindows[entry.id] ?? entry.windowID
        let deliveryPID = original.hostPID
        entry.hostPID = deliveryPID
        lastMoveTrace["deliveryPID"] = Double(deliveryPID)
        guard let source = CGEventSource(stateID: .hidSystemState) else { throw ServiceError.notMoved }
        source.localEventsSuppressionInterval = 0
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag)
        for attempt in 0..<3 {
            guard let originalFrame = currentFrame(for: entry) ?? sourceFrameWithoutRevealing(entry),
                  let edge = statusFrame(named: "MenuBarStudio.Divider", item: divider),
                  let arrow = statusFrame(named: "MenuBarStudio.Entrance", item: entrance) else { throw ServiceError.notVisible }
            let targetName = placement == .shelf ? "MenuBarStudio.Divider" : "MenuBarStudio.Entrance"
            guard let targetID = statusWindowIDs[targetName] else { throw ServiceError.notVisible }
            let point = CGPoint(x: placement == .shelf ? edge.minX - 4 : arrow.maxX + 4, y: arrow.midY)
            lastMoveTrace["destinationX"] = point.x
            lastMoveTrace["boundaryX"] = edge.minX
            lastMoveTrace["sourceWindow"] = Double(entry.windowID)
            lastMoveTrace["targetWindow"] = Double(targetID)
            guard let down = addressedEvent(entry, type: .leftMouseDown,
                    point: CGPoint(x: 20_000, y: 20_000), right: false, source: source),
                  let up = addressedEvent(entry, type: .leftMouseUp, point: point, right: false, source: source),
                  let release = addressedEvent(entry, type: .leftMouseUp,
                    point: CGPoint(x: originalFrame.midX, y: originalFrame.midY), right: false, source: source) else { throw ServiceError.notMoved }
            for event in [down, up, release] {
                event.setIntegerValueField(.mouseEventClickState, value: 0)
            }
            down.flags = .maskCommand
            up.flags = []
            release.flags = []
            address(up, window: targetID, pid: deliveryPID)
            if let drop = directDrop(for: entry, placement: placement) {
                up.location = drop.1
                address(up, window: drop.0, pid: deliveryPID)
                lastMoveTrace["dropWindow"] = Double(drop.0)
                lastMoveTrace["destinationX"] = drop.1.x
            }
            do {
                try await StatusEventDelivery.send(down, to: deliveryPID)
                lastMoveTrace["downMs"] = Date().timeIntervalSince(started) * 1000
                let readyDeadline = Date().addingTimeInterval(0.12)
                while Date() < readyDeadline {
                    try await Task.sleep(nanoseconds: 3_000_000)
                    if let ready = currentFrame(for: entry), ready != originalFrame { break }
                }
                lastMoveTrace["attempt\(attempt)ReadyX"] = currentFrame(for: entry).map { Double($0.minX) }
                try await StatusEventDelivery.send(up, to: deliveryPID)
                lastMoveTrace["upMs"] = Date().timeIntervalSince(started) * 1000
            } catch {
                // Always end a partially delivered drag at its own window.
                try? await StatusEventDelivery.send(release, to: deliveryPID)
                throw error
            }
            var stable = 0
            let verificationDeadline = Date().addingTimeInterval(0.2)
            while Date() < verificationDeadline {
                try await Task.sleep(nanoseconds: 8_000_000)
                let snapshot = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                visibility.sample(values: snapshot.filter { $0[kCGWindowIsOnscreen as String] as? Bool == true })
                func frame(_ id: CGWindowID?) -> CGRect? {
                    guard let id, let info = snapshot.first(where: { $0[kCGWindowNumber as String] as? UInt32 == id }),
                          let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
                    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
                }
                guard let itemFrame = frame(entry.windowID),
                      let boundary = frame(statusWindowIDs["MenuBarStudio.Divider"]),
                      let anchor = frame(statusWindowIDs["MenuBarStudio.Entrance"]) else { continue }
                let side = LayoutPolicy.observedPlacement(item: itemFrame, divider: boundary)
                lastMoveTrace["lastFrameX"] = itemFrame.minX
                lastMoveTrace["lastBoundaryX"] = boundary.minX
                lastMoveTrace["attempt\(attempt)FrameX"] = itemFrame.minX
                lastMoveTrace["attempt\(attempt)AnchorX"] = anchor.minX
                let others = visibleZoneWindows(visibleStatusWindows()).filter { $0.id != entry.windowID }.map(\.frame)
                let firstSlot = placement == .shelf || LayoutPolicy.isFirstVisibleSlot(
                    item: itemFrame, entrance: anchor, otherItems: others)
                let frame = itemFrame
                stable = side == placement && firstSlot ? stable + 1 : 0
                if stable >= 2 {
                    entry.frame = frame; entry.placement = placement; entry.placementVerified = true
                    entry.hostPID = original.hostPID
                    liveWindows[entry.id] = entry.windowID
                    if placement == .visible {
                        visibleItemWindows[entry.id] = entry.windowID
                        hiddenItemWindows.removeValue(forKey: entry.id)
                    } else {
                        visibleItemWindows.removeValue(forKey: entry.id)
                        hiddenItemWindows[entry.id] = entry.windowID
                    }
                    lastMoveTrace["attempts"] = Double(attempt + 1)
                    if let collapseAfter {
                        let changed = collapsed != collapseAfter
                        setCollapsed(collapseAfter)
                        if changed { await settleControls(collapsed: collapseAfter) }
                    }
                    return entry
                }
            }
            lastMoveTrace["attempts"] = Double(attempt + 1)
        }
        throw ServiceError.notMoved
    }

    func cancelPendingMove() { activeWindowServerMove?.cancel() }

    private func moveHosted(_ original: MenuBarEntry, to placement: ItemPlacement, collapseAfter: Bool?) async throws -> MenuBarEntry {
        let started = Date()
        lastMoveTrace = ["directed": 1, "windowServerOnly": 1, "regionExpansions": 0]
        lastMoveMilliseconds = nil; lastCursorDisplacement = nil; lastMoveVisibilitySamples = []
        var entry = original
        entry.windowID = liveWindows[entry.id] ?? entry.windowID
        guard statusFrame(named: "MenuBarStudio.Divider", item: divider) != nil,
              statusFrame(named: "MenuBarStudio.Entrance", item: entrance) != nil,
              let dividerID = statusWindowIDs["MenuBarStudio.Divider"],
              let entranceID = statusWindowIDs["MenuBarStudio.Entrance"] else { throw ServiceError.notVisible }
        let input = WindowServerMove.Input(window: entry.windowID, hostPID: entry.hostPID,
            sourceFrame: currentFrame(for: entry) ?? entry.frame, divider: dividerID, entrance: entranceID,
            placement: placement, hiddenPeers: Set(hiddenItemWindows.filter { $0.key != entry.id }.map(\.value)),
            collapsed: collapsed, started: started)
        let session = WindowServerMoveSession()
        activeWindowServerMove = session
        defer { activeWindowServerMove = nil }
        let outcome = await Task.detached(priority: .userInitiated) {
            await WindowServerMove.run(input, session: session)
        }.value
        lastMoveTrace = outcome.trace; lastMoveMilliseconds = outcome.milliseconds
        lastMoveVisibilitySamples = outcome.samples; lastCursorDisplacement = outcome.cursorDisplacement
        if let error = outcome.error { throw error }
        guard let frame = outcome.frame else { throw ServiceError.notMoved }
        entry.frame = frame; entry.placement = placement; entry.placementVerified = true
        liveWindows[entry.id] = entry.windowID
        if placement == .visible {
            visibleItemWindows[entry.id] = entry.windowID; hiddenItemWindows.removeValue(forKey: entry.id)
        } else {
            visibleItemWindows.removeValue(forKey: entry.id); hiddenItemWindows[entry.id] = entry.windowID
        }
        if let collapseAfter {
            let changed = collapsed != collapseAfter
            setCollapsed(collapseAfter)
            if changed { await settleControls(collapsed: collapseAfter) }
        }
        return entry
    }

    private func directDrop(for entry: MenuBarEntry, placement: ItemPlacement) -> (CGWindowID, CGPoint)? {
        let snapshot = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        func frame(_ id: CGWindowID) -> CGRect? {
            guard let info = snapshot.first(where: { $0[kCGWindowNumber as String] as? UInt32 == id }),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        guard let dividerID = statusWindowIDs["MenuBarStudio.Divider"], let edge = frame(dividerID),
              let arrowID = statusWindowIDs["MenuBarStudio.Entrance"], let arrow = frame(arrowID) else { return nil }
        if placement == .shelf { return (dividerID, CGPoint(x: edge.minX - 4, y: edge.midY)) }
        // Use the nearest actual neighbor, including a read-only system anchor
        // when no managed app remains visible. Never drop across that anchor.
        let candidates = visibleZoneWindows(visibleStatusWindows()).compactMap { window -> (CGWindowID, CGRect)? in
            guard window.id != entry.windowID, window.frame.midX > arrow.midX else { return nil }
            return (window.id, window.frame)
        }
        if let neighbor = candidates.min(by: { $0.1.minX < $1.1.minX }) {
            let sourceFrame = frame(entry.windowID) ?? entry.frame
            // A newly visible item creates space to the left of its neighbor.
            // Reserve that item's actual width before starting the native move.
            let reserve = sourceFrame.midX < arrow.midX ? sourceFrame.width : 0
            return (neighbor.0, CGPoint(x: neighbor.1.minX - reserve - 1, y: neighbor.1.midY))
        }
        return (arrowID, CGPoint(x: arrow.maxX + 1, y: arrow.midY))
    }

    private func sourceFrameWithoutRevealing(_ entry: MenuBarEntry) -> CGRect? {
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
        }
        let app = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let raw = value(app, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID(),
              let children = value(raw as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        let frames = children.prefix(20).compactMap { child -> CGRect? in
            AXUIElementSetMessagingTimeout(child, 0.06)
            guard let rawPoint = value(child, kAXPositionAttribute), CFGetTypeID(rawPoint) == AXValueGetTypeID(),
                  let rawSize = value(child, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero; var size = CGSize.zero
            guard AXValueGetValue(rawPoint as! AXValue, .cgPoint, &point),
                  AXValueGetValue(rawSize as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
            return CGRect(origin: point, size: size)
        }.sorted { $0.minX < $1.minX }
        let ordinal = Int(entry.id.split(separator: "#").last ?? "0") ?? 0
        return frames.dropFirst(ordinal).first
    }

    func click(_ entry: MenuBarEntry, right: Bool = false, modifiers: CGEventFlags = []) async throws {
        guard hasAccessibility else { throw ServiceError.permission }
        if let native27 {
            let before = menuWindowIDs()
            nativeMenuTracking?.stop()
            let tracking = NativeMenuTracking(pid: entry.pid)
            nativeMenuTracking = tracking
            lastNativeMenuObserved = false
            lastNativeMenuItemCount = 0
            lastClickMechanism = ""
            var pointerFallback = false
            let delivery: AXError
            if !modifiers.isEmpty {
                // AX actions cannot carry modifiers. Send the requested native
                // action once rather than silently dropping them or rejecting
                // an otherwise movable application as a protected system item.
                try await clickNative27Pointer(entry, right: right, modifiers: modifiers, backend: native27)
                pointerFallback = true
                delivery = .success
            } else {
                do { delivery = try await native27.press(entry, right: right) }
                catch ServiceError.contextMenuUnavailable where right {
                    // Only an explicitly undelivered context action can fall back.
                    // Never replay an AX success or an ambiguous timeout.
                    try await clickNative27Pointer(entry, right: true, modifiers: [], backend: native27)
                    pointerFallback = true
                    delivery = .success
                }
            }
            for _ in 0..<10 {
                if tracking.observedOpen { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            activeNativeMenuIDs = menuWindowIDs().subtracting(before)
            activeNativeMenuPID = entry.pid
            lastNativeMenuObserved = tracking.observedOpen || !activeNativeMenuIDs.isEmpty || nativePopupVisible(ownedBy: entry.pid)
            lastNativeMenuItemCount = tracking.itemCount
            if delivery == .cannotComplete && !lastNativeMenuObserved { throw ServiceError.notVisible }
            lastClickMechanism = pointerFallback ? "native-context-macOS27" : "accessibility-macOS27"
            if right && !lastNativeMenuObserved { throw ServiceError.contextMenuUnavailable }
            return
        }
        // The controller temporarily reveals only this item when necessary.
        // No global divider expansion is part of native menu activation.
        let frame = try await settledClickableFrame(for: entry)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        // Never send input into a window whose position changed during the reveal.
        guard let verified = currentFrame(for: entry), verified == frame else { throw ServiceError.notVisible }
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        let passthrough: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source?.setLocalEventsFilterDuringSuppressionState(passthrough, state: .eventSuppressionStateSuppressionInterval)
        source?.setLocalEventsFilterDuringSuppressionState(passthrough, state: .eventSuppressionStateRemoteMouseDrag)
        let beforeMenus = menuWindowIDs()
        lastNativeMenuObserved = false
        activeNativeMenuIDs = []
        lastNativeMenuItemCount = 0
        lastClickMechanism = ""
        if modifiers.isEmpty, let item = accessibilityItem(for: entry, frame: frame) {
            let action = right ? "AXShowMenu" : kAXPressAction
            if AXUIElementPerformAction(item, action as CFString) == .success {
                lastClickMechanism = "accessibility"
                try? await Task.sleep(nanoseconds: 150_000_000)
                lastNativeMenuObserved = !menuWindowIDs().subtracting(beforeMenus).isEmpty
                activeNativeMenuIDs = menuWindowIDs().subtracting(beforeMenus)
                lastNativeMenuItemCount = nativeContextMenuItemCount(entry.pid)
                if !right || lastNativeMenuObserved { return }
                // Some apps acknowledge AXShowMenu without opening a window.
                // A context-menu fallback is safe; never repeat a left action.
            }
        }
        lastClickMechanism = "hardware-mouse-event"
        let cursor = CGEvent(source: nil)?.location
        let hidCursor = CGDisplayHideCursor(CGMainDisplayID()) == .success
        defer {
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            if hidCursor { CGDisplayShowCursor(CGMainDisplayID()) }
        }
        CGWarpMouseCursorPosition(point)
        func sendClick(contextAsControl: Bool = false) async {
            let useRightButton = right && !contextAsControl
            for type in [useRightButton ? CGEventType.rightMouseDown : .leftMouseDown,
                         useRightButton ? .rightMouseUp : .leftMouseUp] {
                if let event = CGEvent(mouseEventSource: source, mouseType: type,
                                       mouseCursorPosition: point, mouseButton: useRightButton ? .right : .left) {
                    event.flags = contextAsControl ? modifiers.union(.maskControl) : modifiers
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                    event.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        await sendClick()
        try? await Task.sleep(nanoseconds: 180_000_000)
        lastNativeMenuObserved = !menuWindowIDs().subtracting(beforeMenus).isEmpty
        activeNativeMenuIDs = menuWindowIDs().subtracting(beforeMenus)
        lastNativeMenuItemCount = nativeContextMenuItemCount(entry.pid)
        // Caffeine explicitly supports Control-click as its native context action.
        if right, !lastNativeMenuObserved, entry.bundleID == "net.domzilla.caffeine" {
            lastClickMechanism = "native-control-click"
            await sendClick(contextAsControl: true)
            try? await Task.sleep(nanoseconds: 180_000_000)
            lastNativeMenuObserved = !menuWindowIDs().subtracting(beforeMenus).isEmpty
            activeNativeMenuIDs = menuWindowIDs().subtracting(beforeMenus)
            lastNativeMenuItemCount = nativeContextMenuItemCount(entry.pid)
        }
        logger.info("native menu observed: \(self.lastNativeMenuObserved, privacy: .public)")
        if right && !lastNativeMenuObserved { throw ServiceError.contextMenuUnavailable }
    }

    private func clickNative27Pointer(_ entry: MenuBarEntry, right: Bool, modifiers: CGEventFlags,
                                      backend: NativeMenuBar27) async throws {
        guard let frame = backend.drawnItems()?.first(where: { $0.pid == entry.pid })?.frame,
              frame.width > 0, frame.height > 0 else { throw ServiceError.notVisible }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let controlClick = right && entry.bundleID == "net.domzilla.caffeine"
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        let passthrough: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source?.setLocalEventsFilterDuringSuppressionState(passthrough, state: .eventSuppressionStateSuppressionInterval)
        let useRight = right && !controlClick
        let button: CGMouseButton = useRight ? .right : .left
        let down = useRight ? CGEventType.rightMouseDown : .leftMouseDown
        let up = useRight ? CGEventType.rightMouseUp : .leftMouseUp
        guard let pressed = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: point, mouseButton: button),
              let released = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: point, mouseButton: button),
              backend.drawnItems()?.contains(where: { $0.pid == entry.pid && $0.frame == frame }) == true else {
            throw ServiceError.notVisible
        }
        for event in [pressed, released] {
            event.flags = controlClick ? modifiers.union(.maskControl) : modifiers
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        let cursor = CGEvent(source: nil)?.location
        let hiddenCursor = CGDisplayHideCursor(CGMainDisplayID()) == .success
        defer {
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            if hiddenCursor { CGDisplayShowCursor(CGMainDisplayID()) }
        }
        CGWarpMouseCursorPosition(point)
        pressed.post(tap: .cghidEventTap)
        // Always release this one mouse-down, including task cancellation.
        try? await Task.sleep(nanoseconds: 20_000_000)
        released.post(tap: .cghidEventTap)
    }

    private func nativeContextMenuItemCount(_ pid: pid_t) -> Int {
        let deadline = Date().addingTimeInterval(0.4)
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard Date() < deadline else { return nil }
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        var roots: [AXUIElement] = []
        if let bar = value(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() { roots.append(bar as! AXUIElement) }
        if let focused = value(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let role = value(focused as! AXUIElement, kAXRoleAttribute) as? String, role == "AXMenu" || role == "AXMenuItem" {
            roots.append(focused as! AXUIElement)
        }
        var count = 0, examined = 0
        func visit(_ element: AXUIElement, depth: Int, inMenu: Bool) {
            guard depth < 5, examined < 120, Date() < deadline else { return }
            examined += 1
            AXUIElementSetMessagingTimeout(element, 0.08)
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            if inMenu && role == "AXMenuItem" { count += 1 }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(60) {
                visit(child, depth: depth + 1, inMenu: inMenu || role == "AXMenu")
            }
        }
        for root in roots { visit(root, depth: 0, inMenu: false) }
        return count
    }

    private func accessibilityItem(for entry: MenuBarEntry, frame: CGRect) -> AXUIElement? {
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
            return result
        }
        let app = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let rawBar = value(app, "AXExtrasMenuBar"), CFGetTypeID(rawBar) == AXUIElementGetTypeID(),
              let children = value(rawBar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        return children.first { child in
            guard let rawPoint = value(child, kAXPositionAttribute), CFGetTypeID(rawPoint) == AXValueGetTypeID(),
                  let rawSize = value(child, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return false }
            var point = CGPoint.zero; var size = CGSize.zero
            guard AXValueGetValue(rawPoint as! AXValue, .cgPoint, &point),
                  AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return false }
            let candidate = CGRect(origin: point, size: size)
            return abs(candidate.midX - frame.midX) < 12 && abs(candidate.midY - frame.midY) < 3
        }
    }

    private func addressedEvent(_ entry: MenuBarEntry, type: CGEventType, point: CGPoint,
                                right: Bool, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: right ? .right : .left) else { return nil }
        event.flags = []
        address(event, window: entry.windowID, pid: entry.hostPID)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    private func address(_ event: CGEvent, window id: CGWindowID, pid: pid_t) {
        let window = Int64(id)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
        // WindowServer's destination-window field is also required for hosted status windows.
        if let field = CGEventField(rawValue: 51) { event.setIntegerValueField(field, value: window) }
    }

    private func statusWindow(at point: CGPoint, excluding source: CGWindowID) -> (CGWindowID, pid_t)? {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for value in windows {
            guard let layer = value[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let window = value[kCGWindowNumber as String] as? UInt32, window != source,
                  let pid = value[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point) else { continue }
            return (window, pid)
        }
        return nil
    }

    private func settledClickableFrame(for entry: MenuBarEntry) async throws -> CGRect {
        var previous: CGRect?
        var stableSamples = 0
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 10_000_000)
            guard let frame = currentFrame(for: entry), frame.minX >= 0,
                  frame.width > 0, frame.height > 0,
                  pointIsReachable(CGPoint(x: frame.midX, y: frame.midY)) else {
                previous = nil; stableSamples = 0
                continue
            }
            stableSamples = frame == previous ? stableSamples + 1 : 1
            previous = frame
            if stableSamples >= 3 { return frame }
        }
        throw ServiceError.notVisible
    }

    private func menuWindowIDs() -> Set<UInt32> {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { value in
            guard let layer = value[kCGWindowLayer as String] as? Int, layer > 0, layer < 300,
                  value[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                  let id = value[kCGWindowNumber as String] as? UInt32,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 0, rect.height > 0,
                  layer == Int(CGWindowLevelForKey(.popUpMenuWindow)) || (rect.width > 60 && rect.height > 40) else { return nil }
            return id
        })
    }

    func measuredWidths(_ entries: [MenuBarEntry]) -> [String: Double] {
        Dictionary(entries.filter(\.canMove).map { entry in
            (entry.id, Double(currentFrame(for: entry)?.width ?? entry.frame.width))
        }, uniquingKeysWith: { first, _ in first })
    }

    func refreshMenuBarHost() async -> Bool {
        guard #available(macOS 26, *),
              let host = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let oldPID = host.processIdentifier
        guard kill(oldPID, SIGTERM) == 0 else { return false }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let current = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
               current.processIdentifier != oldPID { return true }
        }
        return false
    }

    func nativeMenuOpen() -> Bool {
        if native27 != nil, let pid = activeNativeMenuPID {
            // AX can retain a closed menu tree, and reading its children can
            // populate it again. Only actual onscreen popup windows hold open.
            let open = nativeMenuTracking?.isOpen == true || nativePopupVisible(ownedBy: pid)
                || !menuWindowIDs().intersection(activeNativeMenuIDs).isEmpty
            if !open { activeNativeMenuPID = nil }
            return open
        }
        return !menuWindowIDs().intersection(activeNativeMenuIDs).isEmpty
    }

    private func nativePopupVisible(ownedBy pid: pid_t) -> Bool {
        let values = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return values.contains {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid
                && $0[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.popUpMenuWindow))
        }
    }
}

enum ServiceError: LocalizedError {
    case permission, unsupported, notVisible, notMoved, contextMenuUnavailable, windowMetadataUnavailable, nativeInstallationRequired
    case nativeLayoutAccessRequired, nativeLayoutConflict, nativeLayoutUnmapped, nativeLayoutUnconfirmed, nativeLayoutNoSpace
    var errorDescription: String? {
        switch self {
        case .permission: return L("需要辅助功能权限才能移动或操作其他应用的图标。")
        case .nativeLayoutAccessRequired: return L("请先授权菜单栏排序文件，才能固定入口并按顺序隐藏或显示图标。")
        case .nativeLayoutConflict: return L("菜单栏排序文件已变化或写入未确认，本次没有继续调整，请刷新重试。")
        case .nativeLayoutUnmapped: return L("尚未找到这个图标的排序记录，请刷新后重试。")
        case .nativeLayoutUnconfirmed: return L("系统尚未确认入口和相邻图标的位置，本次分类未保存。")
        case .nativeLayoutNoSpace: return L("当前屏幕菜单栏空间不足，请先收起其他图标，再显示此图标。")
        case .nativeInstallationRequired: return L("macOS 27 需要从应用程序文件夹运行小屉，才能可靠隐藏和恢复图标。")
        case .windowMetadataUnavailable:
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                return L("当前系统未提供独立的菜单栏窗口，本版本暂无法整理图标。图标保持展开，需要适配新版菜单栏接口。")
            }
            return L("系统未提供菜单栏窗口信息，已保持图标展开。请在权限与帮助中检查屏幕录制权限，然后重新打开小屉。")
        case .unsupported: return L("此系统项目暂不支持移动，可在系统设置中管理。")
        case .notVisible: return L("暂时无法定位这个菜单栏图标，请刷新后重试；刘海遮挡项目暂不能代理点击。")
        case .notMoved: return L("系统未确认图标已移动，分类没有保存。可按住 ⌘ 手动拖过分隔线后刷新。")
        case .contextMenuUnavailable: return L("这个应用暂时无法从浮栏打开原右键菜单，请先将它设为常驻，再在原菜单栏中操作。")
        }
    }
}
