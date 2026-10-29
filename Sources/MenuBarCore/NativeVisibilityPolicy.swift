import Foundation
import CoreGraphics

public enum NativeVisibilityPolicy {
    // Check actual rendered overlaps independently of the entrance-order policy.
    public static func hasOverlappingItems(_ frames: [CGRect], tolerance: CGFloat = 1) -> Bool {
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) where abs(frame.midY - other.midY) < 4 {
                if frame.intersection(other).width > tolerance { return true }
            }
        }
        return false
    }

    public static func allowedBundles(running: Set<String>, hidden: Set<String>, ownBundle: String) -> Set<String> {
        var allowed = running.subtracting(hidden)
        allowed.formUnion(running.filter { $0.hasPrefix("com.apple.") })
        allowed.insert(ownBundle)
        return allowed
    }
}
