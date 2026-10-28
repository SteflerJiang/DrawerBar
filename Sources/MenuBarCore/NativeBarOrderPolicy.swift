import Foundation
import CoreGraphics

public enum NativeBarOrderPolicy {
    public static func owner(of key: String) -> String? {
        guard key.hasPrefix("status:"), let separator = key.range(of: "::") else { return nil }
        return String(key[key.index(key.startIndex, offsetBy: 7)..<separator.lowerBound])
    }

    public static func pinEntrance(positions: [String: Double], entrance: String, activeOwners: Set<String>) -> [String: Double]? {
        guard let current = positions[entrance], current.isFinite else { return nil }
        let others = positions.filter { key, value in
            guard value.isFinite, key != entrance, key != "module:AudioVideoModule" else { return false }
            if let ownerName = owner(of: key) {
                return activeOwners.contains(ownerName) && ownerName != owner(of: entrance)
            }
            return key.hasPrefix("module:")
        }.map(\.value)
        let maximum = others.max() ?? 0
        return current > maximum ? [:] : [entrance: maximum + 32]
    }

    public static func insertAfterEntrance(positions: [String: Double], entrance: String,
                                          targets: [String], activeOwners: Set<String>,
                                          visibleOwners: Set<String>) -> [String: Double]? {
        guard !targets.isEmpty, targets.allSatisfy({ positions[$0] != nil }),
              var edits = pinEntrance(positions: positions, entrance: entrance, activeOwners: activeOwners),
              let originalEntrance = positions[entrance] else { return nil }
        let targetSet = Set(targets)
        let firstOther = positions.filter { key, value in
            guard value.isFinite, key != entrance, !targetSet.contains(key), key != "module:AudioVideoModule" else { return false }
            if let ownerName = owner(of: key) {
                return visibleOwners.contains(ownerName) && ownerName != owner(of: entrance)
            }
            return key.hasPrefix("module:")
        }.map(\.value).max() ?? 0
        var anchor = edits[entrance] ?? originalEntrance
        if anchor - firstOther < Double(targets.count + 1) {
            anchor = max(anchor, firstOther) + Double(targets.count + 1) * 32
            edits[entrance] = anchor
        }
        let ordered = targets.sorted { (positions[$0] ?? 0) > (positions[$1] ?? 0) }
        let step = (anchor - firstOther) / Double(ordered.count + 1)
        for (index, key) in ordered.enumerated() { edits[key] = anchor - Double(index + 1) * step }
        return edits
    }

    public static func isLeading(entrance: CGRect, peers: [CGRect], tolerance: CGFloat = 2) -> Bool {
        !peers.contains { abs($0.midY - entrance.midY) < 4 && $0.midX < entrance.midX - tolerance }
    }

    public static func isImmediateRight(entrance: CGRect, target: CGRect, peers: [CGRect]) -> Bool {
        isLeading(entrance: entrance, peers: peers + [target])
            && target.minX >= entrance.maxX - 2
            && !peers.contains { abs($0.midY - entrance.midY) < 4 && $0.midX > entrance.midX && $0.midX < target.midX - 2 }
    }
}
