import AppKit
import QuartzCore

// The visual entrance stays at its reserved screen position while the native
// host swaps spacer width for the incoming item. The real button remains the
// final click target after the transaction settles.
@MainActor
final class EntranceTransition {
    private let item: NSStatusItem
    private let originalLength: CGFloat
    private let originalImage: NSImage?
    private let originalFrame: CGRect
    private let panel: NSPanel
    private var mirrors: [(NSPanel, CGRect)] = []

    init?(item: NSStatusItem, primaryFrame: CGRect? = nil, otherFrames: [CGRect] = []) {
        guard let button = item.button, let window = button.window, window.frame.height > 0 else { return nil }
        let actualFrame = primaryFrame ?? window.frame
        self.item = item; originalLength = item.length; originalImage = button.image; originalFrame = actualFrame
        panel = NSPanel(contentRect: actualFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = button.effectiveAppearance
        let image = NSImageView(frame: CGRect(x: (actualFrame.width - 18) / 2, y: (actualFrame.height - 18) / 2, width: 18, height: 18))
        image.image = button.image; image.contentTintColor = .labelColor
        panel.contentView = NSView(frame: CGRect(origin: .zero, size: actualFrame.size))
        panel.contentView?.addSubview(image)
        panel.orderFrontRegardless()
        for frame in otherFrames where abs(frame.midY - actualFrame.midY) > 4 || abs(frame.minX - actualFrame.minX) > 4 {
            let mirror = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            mirror.level = panel.level; mirror.backgroundColor = .clear; mirror.isOpaque = false
            mirror.hasShadow = false; mirror.ignoresMouseEvents = true; mirror.hidesOnDeactivate = false
            mirror.animationBehavior = .none
            mirror.collectionBehavior = panel.collectionBehavior; mirror.appearance = panel.appearance
            let image = NSImageView(frame: CGRect(x: (frame.width - 18) / 2, y: (frame.height - 18) / 2, width: 18, height: 18))
            image.image = originalImage; image.contentTintColor = .labelColor
            mirror.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
            mirror.contentView?.addSubview(image); mirror.orderFrontRegardless()
            mirrors.append((mirror, frame))
        }
    }

    func reserve(width: CGFloat) async throws -> CGRect {
        guard let button = item.button, let window = button.window else { throw ServiceError.nativeLayoutUnconfirmed }
        let before = originalFrame
        // Put a real proxy frame on screen before making the original
        // transparent; asynchronous window presentation otherwise leaves a
        // one-frame hole in the entrance during the hand-off.
        panel.contentView?.display(); panel.display()
        for (mirror, _) in mirrors { mirror.contentView?.display(); mirror.display() }
        CATransaction.flush()
        for _ in 0..<12 {
            if panel.occlusionState.contains(.visible), mirrors.allSatisfy({ $0.0.occlusionState.contains(.visible) }) { break }
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        guard panel.occlusionState.contains(.visible), mirrors.allSatisfy({ $0.0.occlusionState.contains(.visible) }) else {
            throw ServiceError.nativeLayoutUnconfirmed
        }
        // An ordered/visible window can precede its first composed image.
        // Allow two display cycles even when remote window sharing is running
        // at 30 fps; keep the original artwork in place throughout this wait.
        try await Task.sleep(nanoseconds: 80_000_000)
        let transparent = NSImage(size: originalImage?.size ?? NSSize(width: 18, height: 18), flipped: false) { _ in true }
        transparent.isTemplate = true; button.image = transparent
        button.needsDisplay = true; window.displayIfNeeded(); CATransaction.flush()
        try await Task.sleep(nanoseconds: 17_000_000)
        let sourceWidth = window.frame.width
        var length = max(1, button.bounds.width) + width
        for _ in 0..<3 {
            item.length = length
            for _ in 0..<25 {
                try await Task.sleep(nanoseconds: 8_000_000)
                if abs((window.frame.width - sourceWidth) - width) <= 2 { break }
            }
            let growth = window.frame.width - sourceWidth
            if abs(growth - width) <= 2 {
                // The proxy window updates its width before its origin on
                // macOS 27. Keep the visual anchored to the known right edge.
                let destination = CGRect(x: before.minX - width, y: before.minY, width: before.width, height: before.height)
                panel.setFrame(destination, display: true)
                for (mirror, original) in mirrors { mirror.setFrame(original.offsetBy(dx: -width, dy: 0), display: true) }
                try await Task.sleep(nanoseconds: 40_000_000)
                return destination
            }
            length += width - growth
        }
        throw ServiceError.nativeLayoutUnconfirmed
    }

    func handOffSpace() { item.length = originalLength }

    func finish() async {
        item.length = originalLength
        item.button?.image = originalImage
        item.button?.needsDisplay = true
        item.button?.window?.displayIfNeeded(); CATransaction.flush()
        try? await Task.sleep(nanoseconds: 34_000_000)
        panel.orderOut(nil)
        for (mirror, _) in mirrors { mirror.orderOut(nil) }
    }

    var frame: CGRect { panel.frame }
    var frames: [CGRect] { [panel.frame] + mirrors.map { $0.0.frame } }
}
