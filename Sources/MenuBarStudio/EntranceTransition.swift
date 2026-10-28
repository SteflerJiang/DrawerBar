import AppKit

// The visual entrance stays at its reserved screen position while the native
// host swaps spacer width for the incoming item. The real button remains the
// final click target after the transaction settles.
@MainActor
final class EntranceTransition {
    private let item: NSStatusItem
    private let originalLength: CGFloat
    private let originalImage: NSImage?
    private let panel: NSPanel
    private var mirrors: [(NSPanel, CGRect)] = []

    init?(item: NSStatusItem, otherFrames: [CGRect] = []) {
        guard let button = item.button, let window = button.window, window.frame.height > 0 else { return nil }
        self.item = item; originalLength = item.length; originalImage = button.image
        panel = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = button.effectiveAppearance
        let image = NSImageView(frame: CGRect(x: (window.frame.width - 18) / 2, y: (window.frame.height - 18) / 2, width: 18, height: 18))
        image.image = button.image; image.contentTintColor = .labelColor
        panel.contentView = NSView(frame: CGRect(origin: .zero, size: window.frame.size))
        panel.contentView?.addSubview(image)
        panel.orderFrontRegardless()
        for frame in otherFrames where abs(frame.midY - window.frame.midY) > 4 || abs(frame.minX - window.frame.minX) > 4 {
            let mirror = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            mirror.level = panel.level; mirror.backgroundColor = .clear; mirror.isOpaque = false
            mirror.hasShadow = false; mirror.ignoresMouseEvents = true; mirror.hidesOnDeactivate = false
            mirror.collectionBehavior = panel.collectionBehavior; mirror.appearance = panel.appearance
            let image = NSImageView(frame: CGRect(x: (frame.width - 18) / 2, y: (frame.height - 18) / 2, width: 18, height: 18))
            image.image = originalImage; image.contentTintColor = .labelColor
            mirror.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
            mirror.contentView?.addSubview(image); mirror.orderFrontRegardless()
            mirrors.append((mirror, frame))
        }
        let transparent = NSImage(size: button.image?.size ?? NSSize(width: 18, height: 18), flipped: false) { _ in true }
        transparent.isTemplate = true
        button.image = transparent
    }

    func reserve(width: CGFloat) async throws -> CGRect {
        guard let button = item.button, let window = button.window else { throw ServiceError.nativeLayoutUnconfirmed }
        let before = window.frame
        var length = max(1, button.bounds.width) + width
        for _ in 0..<3 {
            item.length = length
            for _ in 0..<25 {
                try await Task.sleep(nanoseconds: 8_000_000)
                if abs((window.frame.width - before.width) - width) <= 2 { break }
            }
            let growth = window.frame.width - before.width
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

    func finish() {
        item.length = originalLength
        item.button?.image = originalImage
        panel.orderOut(nil)
        for (mirror, _) in mirrors { mirror.orderOut(nil) }
    }

    var frame: CGRect { panel.frame }
    var frames: [CGRect] { [panel.frame] + mirrors.map { $0.0.frame } }
}
