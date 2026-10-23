import CoreGraphics
import Foundation

/// Bounded transaction diagnostics sharing the placement verification snapshot.
final class MoveVisibilityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let started = Date()
    private let peers: Set<CGWindowID>
    private let checkDivider: Bool
    private let displayBounds: [CGRect]
    private var stopped = false
    private var samples: [[String: Any]] = []

    init(peers: Set<CGWindowID>, checkDivider: Bool) {
        self.peers = peers; self.checkDivider = checkDivider
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success {
            displayBounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        } else { displayBounds = [CGDisplayBounds(CGMainDisplayID())] }
    }

    func sample() {
        let values = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        sample(values: values)
    }

    func sample(values: [[String: Any]]) {
        var exposed: [Int] = []
        var expanded = false
        for value in values {
            // WindowServer can label a hosted window “onscreen” while its
            // frame is thousands of points outside every active display.
            // Count actual intersection, not that flag alone.
            if let id = value[kCGWindowNumber as String] as? UInt32, peers.contains(id),
               let bounds = value[kCGWindowBounds as String] as? [String: Any],
               let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
               displayBounds.contains(where: { $0.intersects(frame) }) { exposed.append(Int(id)) }
            if checkDivider, value[kCGWindowName as String] as? String == "MenuBarStudio.Divider",
               let bounds = value[kCGWindowBounds as String] as? [String: Any],
               let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width < 80 { expanded = true }
        }
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        samples.append(["ms": Date().timeIntervalSince(started) * 1000,
                        "exposedPeers": exposed, "expandedDivider": expanded])
    }

    func finish() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        return samples
    }
}
