import Foundation
import CoreGraphics

public enum NativeBarOrderPolicy {
    public static func itemBootstrap(positions: [String: Double], preferredOwner: String,
                                      alternateOwners: Set<String>) -> [String: Double] {
        var patch: [String: Double] = [:]
        for (key, value) in positions where value.isFinite {
            guard let legacyOwner = owner(of: key), alternateOwners.contains(legacyOwner),
                  legacyOwner != preferredOwner, let separator = key.range(of: "::") else { continue }
            let canonical = "status:\(preferredOwner)" + key[separator.lowerBound...]
            guard positions[canonical] == nil else { continue }
            // Ambiguous imported aliases must not choose an arbitrary value.
            if let other = patch[canonical], other != value { return [:] }
            patch[canonical] = value
        }
        return patch
    }

    public static func entranceBootstrap(positions: [String: Double], preferredOwner: String,
                                         alternateOwners: Set<String>, fallbackPosition: Double) -> [String: Double] {
        let preferred = "status:\(preferredOwner)::MenuBarStudio.Entrance"
        guard positions[preferred] == nil, fallbackPosition.isFinite else { return [:] }
        let legacyPositions = alternateOwners.compactMap {
            positions["status:\($0)::MenuBarStudio.Entrance"]
        }.filter(\.isFinite)
        // Create the current host identity without overwriting imported aliases.
        // A prior Command-drag must not be needed to create our own record.
        return [preferred: max(fallbackPosition, legacyPositions.max() ?? fallbackPosition)]
    }

    public static func entranceKey(positions: [String: Double], preferredOwner: String,
                                   alternateOwners: Set<String>) -> String? {
        let preferred = "status:\(preferredOwner)::MenuBarStudio.Entrance"
        if positions[preferred]?.isFinite == true { return preferred }
        // Upgraded menu-bar preferences can retain the executable/display name
        // as the owner. Only match aliases belonging to this application.
        let candidates = alternateOwners.map { "status:\($0)::MenuBarStudio.Entrance" }
            .filter { positions[$0]?.isFinite == true }
        return candidates.count == 1 ? candidates[0] : nil
    }

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
            guard value.isFinite, key != entrance, !targetSet.contains(key) else { return false }
            // A privacy indicator already to the left stays there. If it lies
            // to the right, the new app must be inserted before it as well.
            if key == "module:AudioVideoModule", value >= (edits[entrance] ?? originalEntrance) { return false }
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
            && target.minX <= entrance.maxX + 3
            && !peers.contains { abs($0.midY - entrance.midY) < 4 && $0.midX > entrance.midX && $0.midX < target.midX - 2 }
    }
}
