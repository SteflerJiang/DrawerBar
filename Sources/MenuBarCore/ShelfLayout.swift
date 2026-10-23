import Foundation

/// The panel and its SwiftUI content share the same single-row measurements.
public struct ShelfLayout {
    public static let tileWidth: CGFloat = 40
    public static let tileHeight: CGFloat = 42
    public static let itemSpacing: CGFloat = 8
    public static let contentPadding: CGFloat = 1
    public static let sectionSpacing: CGFloat = 12
    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 12
    public static let controlWidth: CGFloat = 29
    public static let dividerWidth: CGFloat = 1

    private static var chromeWidth: CGFloat {
        2 * horizontalPadding + 3 * sectionSpacing + dividerWidth + 2 * controlWidth
    }

    public let width: CGFloat
    public let height: CGFloat
    public let viewportWidth: CGFloat
    public let needsHorizontalScrolling: Bool

    public init(itemCount: Int, availableWidth: CGFloat) {
        let available = max(Self.chromeWidth + Self.tileWidth + 2 * Self.contentPadding, availableWidth)
        guard itemCount > 0 else {
            width = min(240, available)
            height = 112
            viewportWidth = 0
            needsHorizontalScrolling = false
            return
        }
        let contentWidth = CGFloat(itemCount) * Self.tileWidth
            + CGFloat(itemCount - 1) * Self.itemSpacing + 2 * Self.contentPadding
        width = min(contentWidth + Self.chromeWidth, available)
        height = Self.tileHeight + 2 * Self.contentPadding + 2 * Self.verticalPadding
        viewportWidth = width - Self.chromeWidth
        needsHorizontalScrolling = contentWidth > viewportWidth
    }
}
