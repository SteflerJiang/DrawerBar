import Foundation

/// Native status-window dimensions are logical points, including their own
/// padding. Keep wide traffic meters intact instead of fitting every item to a square.
public struct ShelfLayout {
    public static let tileWidth: CGFloat = 24
    public static let tileHeight: CGFloat = 30
    public static let itemSpacing: CGFloat = 2
    public static let contentPadding: CGFloat = 1
    public static let sectionSpacing: CGFloat = 8
    public static let horizontalPadding: CGFloat = 10
    public static let verticalPadding: CGFloat = 6
    public static let controlWidth: CGFloat = 26
    public static let dividerWidth: CGFloat = 1

    private static var chromeWidth: CGFloat {
        2 * horizontalPadding + 3 * sectionSpacing + dividerWidth + 2 * controlWidth
    }

    public let width: CGFloat
    public let height: CGFloat
    public let viewportWidth: CGFloat
    public let itemHeight: CGFloat
    public let needsHorizontalScrolling: Bool

    public init(itemCount: Int, availableWidth: CGFloat) {
        self.init(itemWidths: Array(repeating: Self.tileWidth, count: max(0, itemCount)), availableWidth: availableWidth)
    }

    public init(itemWidths: [CGFloat], itemHeight: CGFloat = Self.tileHeight, availableWidth: CGFloat) {
        let available = max(Self.chromeWidth + Self.tileWidth + 2 * Self.contentPadding, availableWidth)
        self.itemHeight = max(Self.tileHeight, itemHeight)
        guard !itemWidths.isEmpty else {
            width = min(240, available)
            height = 64
            viewportWidth = 0
            needsHorizontalScrolling = false
            return
        }
        let contentWidth = itemWidths.reduce(0) { $0 + max(1, $1) }
            + CGFloat(itemWidths.count - 1) * Self.itemSpacing + 2 * Self.contentPadding
        width = min(contentWidth + Self.chromeWidth, available)
        height = self.itemHeight + 2 * Self.contentPadding + 2 * Self.verticalPadding
        viewportWidth = width - Self.chromeWidth
        needsHorizontalScrolling = contentWidth > viewportWidth + 0.5
    }
}
