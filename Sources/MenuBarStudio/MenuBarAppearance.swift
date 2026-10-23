import AppKit
import ScreenCaptureKit

struct MenuBarAppearance {
    var background: NSImage?
    var isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

extension MenuBarService {
    /// Sample only a narrow strip of the real menu bar on the drawer's display.
    /// A per-row median rejects text/glyphs and retains the wallpaper tint and
    /// vertical shading. Only the resulting 1px-wide color strip stays in memory.
    func captureMenuBarAppearance(screen: NSScreen, anchor: CGRect) async -> MenuBarAppearance? {
        guard hasScreenCapture,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let bounds = CGDisplayBounds(displayID)
            let barHeight = min(64, max(24, anchor.height))
            let sampleWidth = min(64, CGFloat(display.width))
            let sampleX = min(max(0, anchor.minX - bounds.minX - 112), CGFloat(display.width) - sampleWidth)
            let options = SCStreamConfiguration()
            options.sourceRect = CGRect(x: sampleX, y: 0, width: sampleWidth, height: barHeight)
            options.width = Int(sampleWidth * 2); options.height = Int(barHeight * 2)
            options.showsCursor = false; options.capturesAudio = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: options)
            let width = image.width, height = image.height
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            var strip = [UInt8](repeating: 255, count: height * 4)
            for row in 0..<height {
                for channel in 0..<3 {
                    let values = (0..<width).map { pixels[(row * width + $0) * 4 + channel] }.sorted()
                    strip[row * 4 + channel] = values[width / 2]
                }
            }
            guard let provider = CGDataProvider(data: Data(strip) as CFData),
                  let gradient = CGImage(width: 1, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
            let middle = (height / 2) * 4
            let luminance = (0.2126 * Double(strip[middle]) + 0.7152 * Double(strip[middle + 1])
                + 0.0722 * Double(strip[middle + 2])) / 255
            return MenuBarAppearance(background: NSImage(cgImage: gradient, size: NSSize(width: 1, height: barHeight)),
                isDark: luminance < 0.55)
        } catch { return nil }
    }
}
