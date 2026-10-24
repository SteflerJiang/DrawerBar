import AppKit
import ApplicationServices
import MenuBarCore

/// A scoped delivery handshake for a hosted status window. No pointer warping,
/// drag trajectory or change to the hidden region is involved.
enum StatusEventDelivery {
    private final class Receipt {
        let event: CGEvent
        let pid: pid_t
        let token = Int64.random(in: 1...Int64.max)
        let wakeToken = Int64.random(in: 1...Int64.max)
        var delivered = false
        var processTap: CFMachPort?
        var sessionTap: CFMachPort?
        init(event: CGEvent, pid: pid_t) { self.event = event; self.pid = pid }
    }

    @MainActor
    static func usesWindowServerRoute(to pid: pid_t) -> Bool {
        MovementPolicy.usesWindowServerRoute(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            hostBundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "")
    }

    @MainActor
    static func send(_ event: CGEvent, to pid: pid_t) async throws {
        if usesWindowServerRoute(to: pid) {
            // A hosted status move needs one WindowServer event. Forwarding an
            // extra copy to the host can independently start its drag preview.
            // The caller verifies native geometry before committing the change.
            event.post(tap: .cgSessionEventTap)
            return
        }
        let receipt = Receipt(event: event, pid: pid)
        event.setIntegerValueField(.eventSourceUserData, value: receipt.token)
        let context = Unmanaged.passUnretained(receipt).toOpaque()
        let processCallback: CGEventTapCallBack = { _, _, incoming, context in
            guard let context else { return Unmanaged.passUnretained(incoming) }
            let r = Unmanaged<Receipt>.fromOpaque(context).takeUnretainedValue()
            let token = incoming.getIntegerValueField(.eventSourceUserData)
            if token == r.token {
                r.delivered = true
                return Unmanaged.passUnretained(incoming)
            }
            if token == r.wakeToken {
                r.event.post(tap: .cgSessionEventTap)
                return nil
            }
            return Unmanaged.passUnretained(incoming)
        }
        let sessionCallback: CGEventTapCallBack = { _, _, incoming, context in
            guard let context else { return Unmanaged.passUnretained(incoming) }
            let r = Unmanaged<Receipt>.fromOpaque(context).takeUnretainedValue()
            if !r.delivered && incoming.getIntegerValueField(.eventSourceUserData) == r.token {
                r.event.postToPid(r.pid)
                return Unmanaged.passUnretained(incoming)
            }
            return Unmanaged.passUnretained(incoming)
        }
        guard let processTap = CGEvent.tapCreateForPid(pid: pid, place: .tailAppendEventTap,
                options: .defaultTap, eventsOfInterest: (1 << CGEventType.null.rawValue) | (1 << event.type.rawValue),
                callback: processCallback, userInfo: context),
              let sessionTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                options: .listenOnly, eventsOfInterest: 1 << event.type.rawValue,
                callback: sessionCallback, userInfo: context),
              let processSource = CFMachPortCreateRunLoopSource(nil, processTap, 0),
              let sessionSource = CFMachPortCreateRunLoopSource(nil, sessionTap, 0),
              let wake = CGEvent(source: nil) else { throw ServiceError.permission }
        receipt.processTap = processTap; receipt.sessionTap = sessionTap
        CFRunLoopAddSource(CFRunLoopGetMain(), processSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), sessionSource, .commonModes)
        defer {
            CFMachPortInvalidate(processTap); CFMachPortInvalidate(sessionTap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), processSource, .commonModes)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), sessionSource, .commonModes)
        }
        CGEvent.tapEnable(tap: processTap, enable: true)
        CGEvent.tapEnable(tap: sessionTap, enable: true)
        wake.setIntegerValueField(.eventSourceUserData, value: receipt.wakeToken)
        wake.postToPid(pid)
        for _ in 0..<50 {
            if receipt.delivered { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        throw ServiceError.notMoved
    }
}
