import Foundation

public enum NativeVisibilityPolicy {
    public static func allowedBundles(running: Set<String>, hidden: Set<String>, ownBundle: String) -> Set<String> {
        var allowed = running.subtracting(hidden)
        allowed.formUnion(running.filter { $0.hasPrefix("com.apple.") })
        allowed.insert(ownBundle)
        return allowed
    }
}
