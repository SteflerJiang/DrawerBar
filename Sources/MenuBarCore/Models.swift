import Foundation
import CoreGraphics

public enum ItemPlacement: String, Codable, CaseIterable {
    case visible, shelf
    public var title: String { self == .visible ? L("常驻菜单栏") : L("收进浮栏") }
}

public enum SpacingPreset: String, Codable, CaseIterable, Identifiable {
    case standard, comfortable, compact, minimal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: return L("默认间隔")
        case .comfortable: return L("较小间隔")
        case .compact: return L("小间隔")
        case .minimal: return L("无间隔")
        }
    }
    public var values: (spacing: Int, padding: Int)? {
        switch self {
        case .standard: return nil
        case .comfortable: return (12, 8)
        case .compact: return (8, 4)
        case .minimal: return (4, 0)
        }
    }
    public var previewGap: Double {
        switch self {
        case .standard: return 28
        case .comfortable: return 21
        case .compact: return 13
        case .minimal: return 6
        }
    }
}

/// Nil is deliberately preserved: an absent override differs from zero.
public struct SpacingSnapshot: Codable, Equatable {
    public var spacing: Int?
    public var padding: Int?
    public init(spacing: Int?, padding: Int?) { self.spacing = spacing; self.padding = padding }
    public var preset: SpacingPreset? {
        SpacingPreset.allCases.first { preset in
            if let values = preset.values { return spacing == values.spacing && padding == values.padding }
            return spacing == nil && padding == nil
        }
    }
}

public struct UserConfiguration: Codable {
    public var schemaVersion = 1
    public var placements: [String: ItemPlacement] = [:]
    public var order: [String] = []
    public var collapseDelay: Double = 1.5
    public var shortcut: String = "commandShiftSpace"
    public var onboardingCompleted = false
    public var originalSpacing: SpacingSnapshot?
    public var lastSpacing: SpacingSnapshot?
    public var pendingSpacingUndo: SpacingSnapshot?
    public var identityVersion: Int?
    public var reopenAppsForSpacing: Bool?
    public var spacingReloadExclusions: [String]?
    public var spacingReloadSelection: [String]?
    public init() {}
    public func placement(for id: String) -> ItemPlacement { placements[id] ?? .visible }
    public func spacingReloadIsSelected(_ bundle: String) -> Bool {
        if let explicit = spacingReloadSelection { return explicit.contains(bundle) }
        guard let legacy = spacingReloadExclusions else { return false }
        return !legacy.contains(bundle)
    }
}

public enum LayoutPolicy {
    /// Hidden native windows can be omitted by WindowServer while their owner
    /// is still running. That omission alone is not a user layout change.
    public static func statusTopologySignature(observed: [UInt32: ItemPlacement], hiddenWindows: Set<UInt32>) -> String {
        var sides = observed
        for id in hiddenWindows where sides[id] == nil { sides[id] = .shelf }
        return sides.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.rawValue)" }.joined(separator: ",")
    }

    /// The OS pins the capture/privacy indicator separately from reorderable
    /// status extras. It is neither a managed app nor an insertion boundary.
    public static func participatesInStatusOrdering(windowName: String, hostBundleID: String) -> Bool {
        !(hostBundleID == "com.apple.controlcenter" && windowName == "AudioVideoModule")
    }

    /// Include system/unmanaged items in slot validation. Ignoring them allows
    /// the sole visible app to be accepted on the far side of Battery or Input.
    public static func isFirstVisibleSlot(item: CGRect, entrance: CGRect, otherItems: [CGRect]) -> Bool {
        guard abs(item.midY - entrance.midY) < 4, item.midX > entrance.midX + 2 else { return false }
        return !otherItems.contains {
            abs($0.midY - entrance.midY) < 4 && $0.midX > entrance.midX + 2 && $0.midX < item.midX - 2
        }
    }

    public static func crossesProtectedItems(item: CGRect, protectedItems: [CGRect]) -> Bool {
        protectedItems.contains { abs($0.midY - item.midY) < 4 && $0.midX < item.midX - 2 }
    }

    public static func placementDestination(_ placement: ItemPlacement, divider: CGRect,
                                            entrance: CGRect, y: CGFloat) -> CGPoint {
        CGPoint(x: placement == .shelf ? divider.minX - 4 : entrance.maxX + 4, y: y)
    }

    public static func entranceIsLeading(divider: CGRect, entrance: CGRect, otherItems: [CGRect]) -> Bool {
        let edge = divider.width < 80 ? divider.midX : divider.maxX - 1
        guard entrance.midX > edge else { return false }
        return !otherItems.contains {
            abs($0.midY - entrance.midY) < 4 && $0.midX > edge && $0.midX < entrance.midX - 2
        }
    }

    public static func itemID(bundle: String, ordinal: Int, previousID: String? = nil) -> String {
        if let previousID, previousID.hasPrefix(bundle + "#") { return previousID }
        return "\(bundle)#\(ordinal)"
    }

    /// Ignore overlapping/transitional frames instead of persisting a guessed category.
    public static func observedPlacement(item: CGRect, divider: CGRect) -> ItemPlacement? {
        guard item.width > 0, divider.width > 0, abs(item.midY - divider.midY) < 4 else { return nil }
        if divider.width < 80 {
            // Hosted status windows include overlapping hit padding on macOS 26.
            // Use their centers, reserving a neutral strip during movement.
            if item.midX < divider.midX - 2 { return .shelf }
            if item.midX > divider.midX + 2 { return .visible }
            return nil
        }
        if item.maxX <= divider.minX + 1 { return .shelf }
        if item.minX >= divider.maxX - 1 { return .visible }
        return nil
    }

    public static func prefersDarkIconBackdrop(red: Double, green: Double, blue: Double) -> Bool {
        0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.62
    }

    public static func windowID(from number: Int) -> UInt32? {
        guard number > 0 else { return nil }
        return UInt32(exactly: number)
    }
    public static func sorted(_ ids: [String], order: [String]) -> [String] {
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        // WindowServer can report both windows during a hosted-item replacement.
        // Keep one stable source identity, even while those windows overlap.
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.enumerated().sorted {
            let l = positions[$0.element] ?? Int.max
            let r = positions[$1.element] ?? Int.max
            return l == r ? $0.offset < $1.offset : l < r
        }.map(\.element)
    }
    /// Reorder one existing identity without changing membership or duplicating it.
    public static func reordered(_ ids: [String], moving id: String, before target: String?) -> [String] {
        guard ids.contains(id), id != target else { return ids }
        if let target, !ids.contains(target) { return ids }
        var result = ids.filter { $0 != id }
        result.insert(id, at: target.flatMap { result.firstIndex(of: $0) } ?? result.endIndex)
        return result
    }
    public static func shouldCollapse(pinned: Bool, pointerInside: Bool, nativeMenuOpen: Bool,
                                      elapsed: Double, delay: Double) -> Bool {
        !pinned && !pointerInside && !nativeMenuOpen && elapsed >= delay
    }
}
