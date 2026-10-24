import CoreGraphics
import Foundation
import MenuBarCore

/// One move owns its events. Cancellation and posting share a lock so quitting
/// cannot leave a mouse-down queued after the cleanup mouse-up.
final class WindowServerMoveSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var dragging = false
    private var release: CGEvent?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func begin(_ event: CGEvent, release: CGEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        self.release = release
        event.post(tap: .cgSessionEventTap)
        dragging = true
        return true
    }

    func end(_ event: CGEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        event.post(tap: .cgSessionEventTap)
        dragging = false
        return true
    }

    func update(_ event: CGEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, dragging else { return false }
        event.post(tap: .cgSessionEventTap)
        return true
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if dragging { release?.post(tap: .cgSessionEventTap); dragging = false }
    }

    func releaseIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        if dragging { release?.post(tap: .cgSessionEventTap); dragging = false }
    }
}

enum WindowServerMove {
    struct Input: Sendable {
        let window: CGWindowID
        let hostPID: Int32
        let sourceFrame: CGRect
        let divider: CGWindowID
        let entrance: CGWindowID
        let placement: ItemPlacement
        let hiddenPeers: Set<CGWindowID>
        let collapsed: Bool
        let started: Date
    }

    // Samples contain only immutable JSON-compatible diagnostic values.
    struct Outcome: @unchecked Sendable {
        let frame: CGRect?
        let error: ServiceError?
        let trace: [String: Double]
        let samples: [[String: Any]]
        let milliseconds: Double
        let cursorDisplacement: CGFloat?
    }

    private struct Window {
        let id: CGWindowID
        let pid: Int32
        let frame: CGRect
        let name: String
        let onscreen: Bool
    }

    static func run(_ input: Input, session: WindowServerMoveSession) async -> Outcome {
        let probe = MoveVisibilityProbe(peers: input.hiddenPeers, checkDivider: input.collapsed)
        probe.sample()
        let cursor = CGEvent(source: nil)?.location
        let hiddenCursor = CGDisplayHideCursor(CGMainDisplayID()) == .success
        var trace: [String: Double] = ["directed": 1, "windowServerOnly": 1,
            "workerStartMs": Date().timeIntervalSince(input.started) * 1000,
            "deliveryPID": Double(input.hostPID), "sourceWindow": Double(input.window)]
        var frame: CGRect?
        var terminalError: ServiceError?
        do { frame = try await perform(input, session: session, probe: probe, trace: &trace) }
        catch let failure as ServiceError { terminalError = failure }
        catch { terminalError = .notMoved }
        session.releaseIfNeeded()
        probe.sample()
        let samples = probe.finish()
        trace["visibilitySamples"] = Double(samples.count)
        trace["peerExposureSamples"] = Double(samples.filter { !($0["exposedPeers"] as? [Int] ?? []).isEmpty }.count)
        trace["regionExpansions"] = Double(samples.filter { $0["expandedDivider"] as? Bool == true }.count)
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        if hiddenCursor { CGDisplayShowCursor(CGMainDisplayID()) }
        let displacement = cursor.flatMap { original in
            CGEvent(source: nil).map { hypot($0.location.x - original.x, $0.location.y - original.y) }
        }
        return Outcome(frame: frame, error: terminalError, trace: trace, samples: samples,
            milliseconds: Date().timeIntervalSince(input.started) * 1000, cursorDisplacement: displacement)
    }

    private static func perform(_ input: Input, session: WindowServerMoveSession,
                                probe: MoveVisibilityProbe, trace: inout [String: Double]) async throws -> CGRect {
        guard let source = CGEventSource(stateID: .hidSystemState) else { throw ServiceError.notMoved }
        source.localEventsSuppressionInterval = 0
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag)
        for attempt in 0..<3 {
            guard !session.isCancelled else { throw ServiceError.notMoved }
            let sourceFrame = currentFrame(input.window) ?? input.sourceFrame
            let before = snapshot()
            let pickupX = input.placement == .visible ? (drop(input, windows: before)?.1.x ?? -20_000) : -20_000
            guard let edge = before.first(where: { $0.id == input.divider }),
                  before.contains(where: { $0.id == input.entrance }),
                  let down = event(input, source: source, type: .leftMouseDown, window: input.window,
                    point: CGPoint(x: pickupX, y: 20_000)),
                  let release = event(input, source: source, type: .leftMouseUp, window: input.window,
                    point: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)) else { throw ServiceError.notVisible }
            down.flags = .maskCommand
            trace["attempts"] = Double(attempt + 1)
            trace["boundaryX"] = edge.frame.minX
            trace["attempt\(attempt)OriginalX"] = sourceFrame.minX
            trace["targetWindow"] = Double(input.placement == .shelf ? input.divider : input.entrance)
            guard session.begin(down, release: release) else { throw ServiceError.notMoved }
            trace["pickupX"] = pickupX
            trace["downMs"] = Date().timeIntervalSince(input.started) * 1000
            let pickupDeadline = Date().addingTimeInterval(0.25)
            var ready = false
            while Date() < pickupDeadline, !session.isCancelled {
                try await Task.sleep(nanoseconds: 3_000_000)
                if let picked = currentFrame(input.window), picked != sourceFrame {
                    trace["attempt\(attempt)ReadyX"] = picked.minX; trace["pickupY"] = picked.minY; ready = true; break
                }
            }
            if !ready {
                session.releaseIfNeeded()
                trace["pickupTimeouts", default: 0] += 1
                continue
            }
            if input.placement == .visible, let initial = drop(input, windows: before),
               let drag = event(input, source: source, type: .leftMouseDragged, window: initial.0,
                    point: CGPoint(x: initial.1.x, y: 20_000)) {
                drag.flags = .maskCommand
                guard session.update(drag) else { throw ServiceError.notMoved }
                let desired = CGRect(x: initial.1.x - sourceFrame.width + 1, y: initial.1.y - sourceFrame.height / 2,
                    width: sourceFrame.width, height: sourceFrame.height)
                let spaceDeadline = Date().addingTimeInterval(0.55)
                var spaceClear = false
                while Date() < spaceDeadline, !session.isCancelled {
                    try await Task.sleep(nanoseconds: 8_000_000)
                    if let anchor = currentFrame(input.entrance) {
                        trace["preDropAnchorX"] = anchor.minX
                        trace["preDropSourceX"] = desired.minX
                        let neighborUnchanged = currentFrame(initial.0).map { abs($0.minX - (initial.1.x + 1)) < 1 } ?? false
                        trace["preDropNeighborStable"] = neighborUnchanged ? 1 : 0
                        if neighborUnchanged && MovementPolicy.entranceArtworkIsClear(item: desired, entrance: anchor) {
                            spaceClear = true; break
                        }
                    }
                }
                trace["preDropSpaceClear"] = spaceClear ? 1 : 0
                guard spaceClear else { throw ServiceError.notMoved }
            }
            let picked = snapshot()
            guard let target = drop(input, windows: picked),
                  let up = event(input, source: source, type: .leftMouseUp,
                    window: target.0, point: target.1) else { throw ServiceError.notVisible }
            up.flags = []
            trace["dropWindow"] = Double(target.0)
            trace["destinationX"] = target.1.x
            trace["attempt\(attempt)DropX"] = target.1.x
            guard session.end(up) else { throw ServiceError.notMoved }
            trace["upMs"] = Date().timeIntervalSince(input.started) * 1000
            let deadline = Date().addingTimeInterval(0.35)
            let settlementDeadline = Date().addingTimeInterval(0.65)
            var verification = MovementVerification()
            var placementConfirmed = false
            while true {
                guard !session.isCancelled else { throw ServiceError.notMoved }
                try await Task.sleep(nanoseconds: 8_000_000)
                let values = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                probe.sample(values: values.filter { $0[kCGWindowIsOnscreen as String] as? Bool == true })
                let windows = parse(values)
                let item = windows.first(where: { $0.id == input.window })?.frame ?? currentFrame(input.window)
                var valid = false
                if let item, let boundary = windows.first(where: { $0.id == input.divider })?.frame,
                   let anchor = windows.first(where: { $0.id == input.entrance })?.frame {
                    let others = visibleZone(input, windows: windows, anchor: anchor).map(\.frame)
                    let firstSlot = input.placement == .shelf || LayoutPolicy.isFirstVisibleSlot(
                        item: item, entrance: anchor, otherItems: others)
                    let clear = input.placement == .shelf || MovementPolicy.entranceArtworkIsClear(item: item, entrance: anchor)
                    let correctPlacement = LayoutPolicy.observedPlacement(item: item, divider: boundary) == input.placement && firstSlot
                    placementConfirmed = correctPlacement
                    valid = correctPlacement && clear
                    trace["lastFrameX"] = item.minX; trace["lastBoundaryX"] = boundary.minX
                    trace["attempt\(attempt)FrameX"] = item.minX; trace["attempt\(attempt)AnchorX"] = anchor.minX
                    trace["entranceOverlap"] = input.placement == .visible ? max(0, anchor.maxX - item.minX) : 0
                    if verification.observe(valid: valid) {
                        trace["confirmationSamples"] = Double(verification.consecutiveValidSamples)
                        return item
                    }
                } else { verification.observe(valid: false) }
                // Confirm a late valid sample once more instead of replaying an
                // already completed move when a deadline ends between samples.
                if !placementConfirmed && verification.shouldRetry(deadlinePassed: Date() >= deadline) { break }
                // Never replay a correctly positioned item just to finish a
                // neighbor animation. Bound that wait and let recovery reconcile.
                if Date() >= settlementDeadline { throw ServiceError.notMoved }
            }
        }
        throw ServiceError.notMoved
    }

    private static func drop(_ input: Input, windows: [Window]) -> (CGWindowID, CGPoint)? {
        guard let edge = windows.first(where: { $0.id == input.divider }),
              let arrow = windows.first(where: { $0.id == input.entrance }) else { return nil }
        if input.placement == .shelf { return (edge.id, CGPoint(x: edge.frame.minX - 4, y: edge.frame.midY)) }
        let candidates = visibleZone(input, windows: windows, anchor: arrow.frame)
            .filter { $0.frame.midX > arrow.frame.midX }
        if let neighbor = candidates.min(by: { $0.frame.minX < $1.frame.minX }) {
            let x = MovementPolicy.insertionX(beforeNeighbor: neighbor.frame.minX, sourceWidth: 0,
                sourceIsHidden: true, pickupAtLeftEdge: true)
            return (neighbor.id, CGPoint(x: x, y: neighbor.frame.midY))
        }
        return (arrow.id, CGPoint(x: arrow.frame.maxX + 1, y: arrow.frame.midY))
    }

    private static func visibleZone(_ input: Input, windows: [Window], anchor: CGRect) -> [Window] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let bounds: CGRect
        if CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success,
           let display = displays.prefix(Int(count)).first(where: { CGDisplayBounds($0).contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) {
            bounds = CGDisplayBounds(display)
        } else { bounds = CGDisplayBounds(CGMainDisplayID()) }
        return windows.filter {
            $0.onscreen && $0.id != input.window && $0.id != input.divider && $0.id != input.entrance
                && !$0.name.hasPrefix("MenuBarStudio.") && !input.hiddenPeers.contains($0.id)
                && !($0.name == "AudioVideoModule" && $0.pid == input.hostPID)
                && $0.frame.width < 1000 && abs($0.frame.midY - anchor.midY) < 4
                && bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
    }

    private static func event(_ input: Input, source: CGEventSource, type: CGEventType,
                              window: CGWindowID, point: CGPoint) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(input.hostPID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        if let field = CGEventField(rawValue: 51) { event.setIntegerValueField(field, value: Int64(window)) }
        return event
    }

    private static func currentFrame(_ id: CGWindowID) -> CGRect? {
        let values = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let value = values.first(where: { $0[kCGWindowNumber as String] as? UInt32 == id }),
              let bounds = value[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private static func snapshot() -> [Window] {
        parse(CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
    }

    private static func parse(_ values: [[String: Any]]) -> [Window] {
        values.compactMap { value in
            guard value[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = value[kCGWindowNumber as String] as? UInt32,
                  let pid = value[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0, frame.height > 0, frame.height < 64 else { return nil }
            return Window(id: id, pid: pid, frame: frame, name: value[kCGWindowName as String] as? String ?? "",
                onscreen: value[kCGWindowIsOnscreen as String] as? Bool == true)
        }
    }
}
