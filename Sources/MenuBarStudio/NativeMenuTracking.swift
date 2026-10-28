import AppKit
import ApplicationServices

@MainActor
final class NativeMenuTracking {
    private var observer: AXObserver?
    private var menus: [AXUIElement] = []
    private(set) var observedOpen = false
    private(set) var itemCount = 0
    private(set) var available = false
    var isOpen: Bool { !menus.isEmpty }

    init(pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<NativeMenuTracking>.fromOpaque(context).takeUnretainedValue()
                    .receive(element, notification: notification as String)
            }
        }, &created) == .success, let created else { return }
        observer = created
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let opened = AXObserverAddNotification(created, app, kAXMenuOpenedNotification as CFString, context)
        let closed = AXObserverAddNotification(created, app, kAXMenuClosedNotification as CFString, context)
        available = opened == .success && closed == .success
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func receive(_ element: AXUIElement, notification: String) {
        if notification == kAXMenuOpenedNotification {
            observedOpen = true
            if !menus.contains(where: { CFEqual($0, element) }) { menus.append(element) }
            var children: CFTypeRef?
            AXUIElementSetMessagingTimeout(element, 0.12)
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
                itemCount = max(itemCount, (children as? [AXUIElement])?.count ?? 0)
            }
        } else if notification == kAXMenuClosedNotification {
            if let index = menus.firstIndex(where: { CFEqual($0, element) }) { menus.remove(at: index) }
            else { menus.removeAll() }
        }
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; menus.removeAll()
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
