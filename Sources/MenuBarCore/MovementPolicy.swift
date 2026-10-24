import Foundation
import CoreGraphics

/// Limit the hosted-window route to the OS/host combination verified natively.
/// Older app-owned status windows retain their existing delivery handshake.
public enum MovementPolicy {
    public static func usesWindowServerRoute(macOSMajorVersion: Int, hostBundleID: String) -> Bool {
        macOSMajorVersion == 26 && hostBundleID == "com.apple.controlcenter"
    }
    /// Verify the drawer artwork rather than the larger, overlapping native
    /// hit rectangle. Its centered outline is 15.5 pt wide including stroke.
    public static func entranceArtworkIsClear(item: CGRect, entrance: CGRect) -> Bool {
        entrance.midX + 15.5 / 2 <= item.minX
    }
    /// Right-edge pickup temporarily shifts the visible group by the source
    /// width. Left-edge pickup leaves the neighbor in place; never subtract it twice.
    public static func insertionX(beforeNeighbor x: CGFloat, sourceWidth: CGFloat,
                                  sourceIsHidden: Bool, pickupAtLeftEdge: Bool) -> CGFloat {
        let reservation = !pickupAtLeftEdge && sourceIsHidden ? sourceWidth : 0
        return x - reservation - 1
    }
}

/// A late valid observation gets its confirming sample, rather than causing
/// another native drag solely because the deadline ended between observations.
public struct MovementVerification: Sendable {
    public private(set) var consecutiveValidSamples = 0
    public init() {}
    @discardableResult
    public mutating func observe(valid: Bool) -> Bool {
        consecutiveValidSamples = valid ? consecutiveValidSamples + 1 : 0
        return consecutiveValidSamples >= 2
    }
    public func shouldRetry(deadlinePassed: Bool) -> Bool {
        deadlinePassed && consecutiveValidSamples == 0
    }
}
