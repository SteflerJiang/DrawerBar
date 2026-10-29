import AppKit
import Darwin
import UniformTypeIdentifiers
import MenuBarCore


extension AppController {
    @objc func exportDiagnosticsAction() { exportDiagnostics() }

    func exportDiagnostics() {
        guard !exportingDiagnostics else { return }
        let panel = NSSavePanel()
        panel.title = L("导出诊断信息")
        panel.allowedContentTypes = [.zip]; panel.canCreateDirectories = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "DrawerBar-Diagnostics-" + formatter.string(from: Date()) + ".zip"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = L("包含应用名称、图标位置及错误；不含截图、录屏或授权凭证，仅保存到本机。")
        exportingDiagnostics = true; diagnosticExportNotice = nil
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destination = panel.url else { self.exportingDiagnostics = false; return }
            // No refresh, move or permission request: exporting is read-only.
            let context = self.diagnosticContext()
            guard let data = try? JSONSerialization.data(withJSONObject: context) else {
                self.exportingDiagnostics = false; self.diagnosticExportNotice = L("诊断信息无法序列化，请重试。"); return
            }
            let support = self.store.url.deletingLastPathComponent()
            Task {
                do {
                    try await Task.detached(priority: .utility) { try DiagnosticArchive.write(context: data, support: support, destination: destination) }.value
                    self.diagnosticExportNotice = L("诊断包已保存，可将文件发送给开发者。")
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                } catch { self.diagnosticExportNotice = L("导出失败：%@", error.localizedDescription) }
                self.exportingDiagnostics = false
            }
        }
    }

    private func diagnosticContext() -> [String: Any] {
        func sysctlText(_ name: String) -> String {
            var length = 0
            guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0, length < 4096 else { return "unavailable" }
            var bytes = [CChar](repeating: 0, count: length)
            guard sysctlbyname(name, &bytes, &length, nil, 0) == 0 else { return "unavailable" }
            return String(cString: bytes)
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let context: [String: Any] = [
            "schemaVersion": 1, "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "environment": ["appVersion": info["CFBundleShortVersionString"] ?? "unknown",
                "appBuild": info["CFBundleVersion"] ?? "unknown", "buildChannel": "local-diagnostics",
                "os": ProcessInfo.processInfo.operatingSystemVersionString, "osBuild": sysctlText("kern.osversion"),
                "hardwareModel": sysctlText("hw.model"), "chip": sysctlText("machdep.cpu.brand_string"),
                "architecture": "arm64", "installedInApplications": Bundle.main.bundleURL.path.hasPrefix("/Applications/"),
                "languages": Locale.preferredLanguages],
            "permissions": ["accessibility": service.hasAccessibility, "screenCapture": service.hasScreenCapture,
                "orderingFile": service.nativeLayoutAccessAvailable],
            "state": ["paused": paused, "busyID": busyID as Any? ?? NSNull(), "refreshing": refreshing,
                "spacingApplying": spacingApplying, "shelfPresented": shelfPresented,
                "message": message as Any? ?? NSNull(), "conflictingManagers": conflictingManagerNames],
            "screens": NSScreen.screens.enumerated().map { index, screen in
                ["index": index, "x": screen.frame.minX, "y": screen.frame.minY,
                 "width": screen.frame.width, "height": screen.frame.height, "scale": screen.backingScaleFactor,
                 "safeAreaTop": screen.safeAreaInsets.top, "visibleX": screen.visibleFrame.minX,
                 "visibleY": screen.visibleFrame.minY, "visibleWidth": screen.visibleFrame.width,
                 "visibleHeight": screen.visibleFrame.height,
                 "rightSafeX": screen.auxiliaryTopRightArea?.minX as Any? ?? NSNull()] as [String: Any]
            },
            "icons": entries.map { ["id": $0.id, "name": $0.name, "bundle": $0.bundleID, "pid": Int($0.pid),
                "placement": $0.placement.rawValue, "verified": $0.placementVerified, "canMove": $0.canMove,
                "frame": ["x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width, "height": $0.frame.height]] as [String: Any] },
            "arrangement": service.arrangementSnapshot(entries)
        ]
        return context
    }
}
