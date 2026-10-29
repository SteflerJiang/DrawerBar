import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import ServiceManagement
import MenuBarCore

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case items, appearance, general, permissions
    var title: String {
        switch self { case .items: return L("图标整理"); case .appearance: return L("菜单栏外观"); case .general: return L("通用设置"); case .permissions: return L("权限与帮助") }
    }
    var id: String { rawValue }
    var symbol: String {
        switch self { case .items: return "menubar.rectangle"; case .appearance: return "paintbrush.pointed"; case .general: return "gearshape"; case .permissions: return "questionmark.circle" }
    }
}

@MainActor
final class AppController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    @Published var page: SettingsPage = .items
    @Published var entries: [MenuBarEntry] = []
    @Published var config: UserConfiguration
    @Published var accessibility = false
    @Published var screenCapture = false
    @Published var refreshing = false
    @Published var busyID: String?
    @Published var message: String?
    @Published var paused = false
    @Published var pinned = false
    @Published var selectedSpacing: SpacingPreset = .standard
    @Published var currentSpacing: SpacingSnapshot
    @Published var spacingNotice: String?
    @Published var spacingApplying = false
    @Published var onboarding = true
    @Published var onboardingStep = 0
    @Published var onboardingSelected: String?
    @Published var loginEnabled = false
    @Published var shortcutNotice: String?
    @Published var shelfPresented = false
    @Published var shelfAppearance = MenuBarAppearance()
    let service = MenuBarService()
    let store = ConfigurationStore()
    let spacing = SpacingPreferences()
    var settingsWindow: NSWindow?
    var shelfPanel: NSPanel?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var outsideSince: Date?
    private var nativeActionUntil: Date?
    private let hotkey = HotkeyManager()
    private var isLaunching = true
    @Published var onboardingTrial: String?
    @Published var onboardingTrialAccessed = false
    private var temporaryNativeEntry: MenuBarEntry?
    private var permissionRestorePending = false
    private var lastSettingsOnboarding: Bool?
    private var escapeMonitorInstalled = false
    private var lastLayoutCheck = Date.distantPast
    private var lastPermissionCheck = Date.distantPast
    private var lastLayoutSignature: String?
    private var presentingShelf = false
    private var lastShortcut = Date.distantPast
    private var shelfScreenNumber: NSNumber?
    private var shelfGeneration = 0
    private var shelfArtworkTask: Task<Void, Never>?
    private var lastSnapshotRefresh = Date.distantPast
    private var deferredShelfRefresh = false
    private var shelfClosedAt = Date.distantPast

    override init() {
        var saved = store.load()
        var seen = Set<String>()
        saved.order = saved.order.filter { saved.placement(for: $0) == .shelf && seen.insert($0).inserted }
        let initialSpacing = SpacingPreferences().read()
        config = saved
        currentSpacing = initialSpacing
        selectedSpacing = initialSpacing.preset ?? .standard
        onboarding = !saved.onboardingCompleted
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: L("小屉"))
        let settings = NSMenuItem(title: L("设置…"), action: #selector(openItems), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        let openShelf = NSMenuItem(title: L("打开浮栏"), action: #selector(toggleShelfAction), keyEquivalent: "")
        openShelf.target = self; appMenu.addItem(openShelf)
        appMenu.addItem(NSMenuItem(title: L("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("退出小屉"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        let entrance = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        entrance.autosaveName = "MenuBarStudio.Entrance"
        entrance.button?.image = service.entranceImage
        entrance.button?.imageScaling = .scaleProportionallyDown
        entrance.button?.toolTip = L("小屉：单击展开，右键打开菜单")
        entrance.button?.setAccessibilityLabel(L("小屉"))
        entrance.button?.setAccessibilityHelp(L("展开或收起图标浮栏；右键打开设置、暂停和退出菜单"))
        entrance.button?.target = self
        entrance.button?.action = #selector(statusClicked)
        entrance.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let divider = NSStatusBar.system.statusItem(withLength: 1)
        divider.autosaveName = "MenuBarStudio.Divider"
        divider.button?.image = nil
        divider.button?.toolTip = nil
        if service.usesNative27 { divider.isVisible = false }
        service.entrance = entrance; service.divider = divider
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appActivated), name: NSApplication.didBecomeActiveNotification, object: nil)
        hotkey.onPress = { [weak self] source in self?.triggerShortcut(source: source) }
        registerShortcut()
        loginEnabled = SMAppService.mainApp.status == .enabled
        installMonitors()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        showSettings()
        Task {
            await refresh(restoreSaved: true, cause: "startup")
            isLaunching = false
            // Keep the boundary constant even when the shelf becomes empty;
            // resizing it after the last move can restart WindowServer ordering.
            service.setCollapsed(!paused && accessibility)
            if CommandLine.arguments.contains("--native-self-check") { startNativeSmokeCheck() }
            if CommandLine.arguments.contains("--native-order-check") { startNativeOrderCheck() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        service.cancelPendingMove()
        service.setCollapsed(false)
        shelfPanel?.close()
        shelfArtworkTask?.cancel()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        hotkey.unregister(); timer?.invalidate(); persist()
    }

    @discardableResult
    func persist() -> Bool {
        do { try store.save(config); return true }
        catch { message = L("配置未能保存：%@", error.localizedDescription); return false }
    }

    func showSettings(_ target: SettingsPage? = nil) {
        if let target { page = target; onboarding = false }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("小屉")
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 880, height: 650)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: RootView().environmentObject(self))
            window.center(); settingsWindow = window
        }
        resizeSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func resizeSettingsWindow() {
        guard let window = settingsWindow else { return }
        guard lastSettingsOnboarding != onboarding else { return }
        lastSettingsOnboarding = onboarding
        window.minSize = onboarding ? NSSize(width: 620, height: 720) : NSSize(width: 880, height: 650)
        window.setContentSize(onboarding ? NSSize(width: 640, height: 780) : NSSize(width: 1000, height: 720))
        window.center()
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let menu = NSMenu(); menu.delegate = self
            for (title, selector) in [(L("打开图标整理"), #selector(openItems)), (L("菜单栏外观"), #selector(openAppearance)),
                                       (paused ? L("继续整理") : L("暂停整理，展开全部"), #selector(togglePauseAction)),
                                       (L("显示首次引导"), #selector(showOnboarding)), (L("退出小屉"), #selector(quit))] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            service.entrance?.menu = menu
            service.entrance?.button?.performClick(nil)
        } else { toggleShelf() }
    }
    func menuDidClose(_ menu: NSMenu) { service.entrance?.menu = nil }
    @objc func openItems() { showSettings(.items) }
    @objc func openAppearance() { showSettings(.appearance) }
    @objc func toggleShelfAction() { toggleShelf() }
    @objc func togglePauseAction() { togglePause() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showOnboarding() { onboardingTrial = nil; onboardingTrialAccessed = false; onboarding = true; onboardingStep = 0; showSettings() }
    @objc func displayChanged() { closeShelf(); Task { await refresh(cause: "display-change") } }
    @objc func woke() { Task { try? await Task.sleep(nanoseconds: 800_000_000); await refresh() } }
    @objc func appChanged() { Task { try? await Task.sleep(nanoseconds: 600_000_000); await refresh(restoreSaved: true, cause: "owner-change") } }
    @objc func appActivated() { checkPermissions() }
    @objc func spaceChanged() { closeShelf(); Task { await refresh(cause: "space-change") } }

    func checkPermissions() {
        let previous = accessibility
        accessibility = service.hasAccessibility; screenCapture = service.hasScreenCapture
        if !accessibility {
            if previous { permissionRestorePending = true; closeShelf() }
            service.setCollapsed(false)
        } else if !previous && !isLaunching {
            permissionRestorePending = true
            Task { await refresh(captureArtwork: false, cause: "permission-restored") }
        }
        if accessibility && !escapeMonitorInstalled {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    if self.matchesShortcut(event) { self.triggerShortcut(source: "global-monitor") }
                    else if event.keyCode == 53 { self.closeShelf() }
                }
            }) { monitors.append(monitor); escapeMonitorInstalled = true }
        }
    }

    func refresh(restoreSaved: Bool = false, captureArtwork: Bool = true, cause: String = "refresh") async {
        guard !refreshing, !spacingApplying, busyID == nil, temporaryNativeEntry == nil else { return }
        refreshing = true; defer { refreshing = false }
        checkPermissions()
        let previousOwners = Dictionary(entries.map { ($0.id, $0.pid) }, uniquingKeysWith: { first, _ in first })
        var snapshot = await discoverReadyEntries(existing: entries)
        do {
            try await service.ensureLeadingEntrance()
            if message == L("未能将小屉入口放到常驻图标左侧，请刷新后重试。")
                || message == ServiceError.windowMetadataUnavailable.localizedDescription
                || message == ServiceError.nativeLayoutAccessRequired.localizedDescription { message = nil }
        }
        catch ServiceError.windowMetadataUnavailable { message = ServiceError.windowMetadataUnavailable.localizedDescription }
        catch let error as ServiceError where service.usesNative27 { message = error.localizedDescription }
        catch { message = L("未能将小屉入口放到常驻图标左侧，请刷新后重试。") }
        for index in snapshot.indices {
            if let frame = service.currentFrame(for: snapshot[index]) { snapshot[index].frame = frame }
        }
        let restoring = Set(snapshot.filter {
            $0.canMove && (isLaunching || permissionRestorePending || (config.placements[$0.id] == nil && previousOwners[$0.id] == nil) || (restoreSaved && previousOwners[$0.id] != $0.pid))
        }.map(\.id))
        let desired = Dictionary(snapshot.filter { restoring.contains($0.id) }.map { ($0.id, config.placement(for: $0.id)) }, uniquingKeysWith: { first, _ in first })
        snapshot = await reconcilePlacements(snapshot, restoring: restoring)
        // A visible app can still be misplaced inside the read-only system
        // group. Repair only that app; never move Battery/Input or rewrite a
        // user's order within the managed group.
        if accessibility && !paused {
            let misplaced = Set(service.visibleItemsCrossingProtectedBoundary())
            for index in snapshot.indices where snapshot[index].canMove && snapshot[index].placement == .visible
                && misplaced.contains(snapshot[index].id) {
                do { snapshot[index] = try await service.move(snapshot[index], to: .visible) }
                catch { message = L("未能恢复 %@ 的位置：%@", snapshot[index].name, error.localizedDescription) }
            }
        }
        permissionRestorePending = false
        if captureArtwork {
            let images = await service.capture(snapshot)
            for index in snapshot.indices {
                if let image = images[snapshot[index].windowID] {
                    snapshot[index].trayImage = image
                    snapshot[index].trayNeedsDarkBackdrop = service.needsDarkBackdrop(image)
                }
            }
        }
        // Publish one snapshot: the settings and shelf always read the same list.
        entries = snapshot
        lastSnapshotRefresh = Date()
        deferredShelfRefresh = false
        if accessibility {
            config.placements = config.placements.filter { !$0.key.hasPrefix("com.apple.controlcenter#") }
            for entry in entries where entry.canMove && entry.placementVerified {
                if let intended = desired[entry.id], intended != entry.placement { continue }
                config.placements[entry.id] = entry.placement
            }
            config.identityVersion = 2
        }
        if !isLaunching { persist() }
        if !isLaunching && !paused && nativeActionUntil == nil {
            service.setCollapsed(accessibility)
        }
        lastLayoutSignature = service.layoutSignature()
        if shelfPresented { sizeShelf() }
        recordDiagnostic("layoutSync", extra: ["cause": cause, "collapsed": service.collapsed, "paused": paused,
            "discovery": service.discoveryDiagnostics(),
            "arrangement": service.arrangementSnapshot(entries),
            "items": entries.filter(\.canMove).map { ["id": $0.id, "placement": $0.placement.rawValue,
                "observed": $0.placementVerified] as [String: Any] }])
    }

    private func discoverReadyEntries(existing: [MenuBarEntry]) async -> [MenuBarEntry] {
        let expected = Set(config.placements.keys.compactMap { id -> String? in
            guard let bundle = id.split(separator: "#").first.map(String.init), !bundle.hasPrefix("com.apple."),
                  NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains(where: { !$0.isTerminated }) else { return nil }
            return bundle
        }).count
        var candidate = existing
        let minimumPasses = isLaunching || config.identityVersion == nil ? 2 : 1
        for pass in 0..<6 {
            await service.resolveHostedSources()
            candidate = service.discover(existing: candidate, config: config)
            if !accessibility || (pass + 1 >= minimumPasses && candidate.filter(\.canMove).count >= expected) { break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return candidate
    }

    private func reconcilePlacements(_ snapshot: [MenuBarEntry], restoring ids: Set<String>) async -> [MenuBarEntry] {
        guard accessibility, !ids.isEmpty else { return snapshot }
        var result = snapshot
        let wasCollapsed = service.collapsed
        var failed = false
        for index in result.indices where ids.contains(result[index].id) {
            let entry = result[index]
            let target = config.placement(for: entry.id)
            let newVisible = !isLaunching && config.placements[entry.id] == nil && target == .visible
            let firstSlot = service.usesNative27 || !newVisible || ((service.arrangementSnapshot(result)["firstRightWindow"] as? Int) == Int(entry.windowID))
            guard entry.placement != target || !entry.placementVerified || !firstSlot else { continue }
            do {
                result[index] = try await service.move(entry, to: target,
                    collapseAfter: service.usesNative27 ? !paused && accessibility : nil)
            } catch {
                failed = true
                message = L("未能恢复 %@ 的位置：%@", entry.name, error.localizedDescription)
            }
        }
        if !failed { service.setCollapsed(service.usesNative27 ? !paused && accessibility : wasCollapsed) }
        return result
    }

    func setPlacement(_ entry: MenuBarEntry, _ placement: ItemPlacement, onSuccess: (() -> Void)? = nil) {
        guard busyID == nil, !refreshing, !presentingShelf, !spacingApplying, temporaryNativeEntry == nil, placement != entry.placement else { return }
        guard accessibility else { message = ServiceError.permission.localizedDescription; page = .permissions; return }
        let started = Date()
        busyID = entry.id
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index].placement = placement }
        if shelfPresented { sizeShelf() }
        Task {
            var verified = false
            do {
                let confirmed = try await service.move(entry, to: placement,
                    collapseAfter: !paused && accessibility)
                verified = true
                if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = confirmed }
                config.placements[entry.id] = placement
                config.order.removeAll { $0 == entry.id }
                if placement == .shelf { config.order.append(entry.id) }
                if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].placement = placement }
                if persist() { message = nil }
                service.setCollapsed(!paused && accessibility)
                onSuccess?()
            } catch {
                if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index].placement = entry.placement }
                message = error.localizedDescription; service.setCollapsed(!paused && accessibility)
            }
            busyID = nil
            if shelfPresented { sizeShelf() }
            if let i = entries.firstIndex(where: { $0.id == entry.id }), let frame = service.currentFrame(for: entry) {
                entries[i].frame = frame
            }
            // A verified move already updated both the native layout and entries.
            // Do not trigger another full AX scan for that same topology. Failed
            // moves still invalidate the signature so idle recovery can reconcile.
            lastLayoutSignature = verified ? service.layoutSignature() : nil
            recordDiagnostic("placement", entry: entry, extra: ["verified": verified, "requestedPlacement": placement.rawValue,
                "operationMilliseconds": Date().timeIntervalSince(started) * 1000,
                "visibilitySamples": service.lastMoveVisibilitySamples,
                "arrangement": service.arrangementSnapshot(entries)])
        }
    }

    var nativeActionInProgress: Bool { temporaryNativeEntry != nil }
    var conflictingManagerNames: [String] {
        let known: Set<String> = ["ibar", "ice", "bartender", "hidden bar", "barbee"]
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != getpid(), let name = app.localizedName, known.contains(name.lowercased()) else { return nil }
            return name
        }.sorted()
    }

    func dropEntry(_ id: String, into placement: ItemPlacement, before target: String?) {
        guard let entry = entries.first(where: { $0.id == id }), busyID == nil, !refreshing, !spacingApplying, temporaryNativeEntry == nil else { return }
        if entry.placement != placement {
            setPlacement(entry, placement) { [weak self] in
                if placement == .shelf { self?.reorder(id, before: target) }
            }
        } else if placement == .shelf { reorder(id, before: target) }
    }

    func reorder(_ from: String, before to: String?) {
        guard let source = entries.first(where: { $0.id == from }), source.placement == .shelf,
              busyID == nil || busyID == from else { return }
        if let to { guard from != to, entries.first(where: { $0.id == to })?.placement == .shelf else { return } }
        let hiddenIDs = entries.filter { $0.canMove && $0.placement == .shelf }.map(\.id)
        let order = LayoutPolicy.reordered(hiddenIDs, moving: from, before: to)
        config.order = order
        let map = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        entries = LayoutPolicy.sorted(entries.map(\.id), order: order).compactMap { map[$0] }; persist()
        if shelfPresented { sizeShelf() }
        recordDiagnostic("reorder", extra: ["from": from, "before": to as Any? ?? NSNull(), "order": order])
    }

    func moveShelfItem(_ id: String, offset: Int) {
        let hidden = entries.filter { $0.canMove && $0.placement == .shelf }.map(\.id)
        guard let index = hidden.firstIndex(of: id) else { return }
        if offset < 0, index > 0 { reorder(id, before: hidden[index - 1]) }
        else if offset > 0, index + 1 < hidden.count { reorder(id, before: index + 2 < hidden.count ? hidden[index + 2] : nil) }
    }

    func resetArrangement() {
        guard busyID == nil, !refreshing, !spacingApplying, temporaryNativeEntry == nil else { return }
        guard accessibility else { message = ServiceError.permission.localizedDescription; page = .permissions; return }
        let backup = store.url.deletingLastPathComponent().appendingPathComponent("configuration-before-reset.json")
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        } catch { message = L("无法保存恢复前的备份，未修改整理规则。"); return }
        busyID = "reset"
        Task {
            var failed = Set<String>()
            for entry in entries where entry.canMove && entry.placement == .shelf {
                do {
                    let confirmed = try await service.move(entry, to: .visible, collapseAfter: !paused && accessibility)
                    if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = confirmed }
                } catch { failed.insert(entry.id) }
            }
            config.placements = config.placements.filter { failed.contains($0.key) }
            config.order = []
            for entry in entries where entry.canMove && !failed.contains(entry.id) { config.placements[entry.id] = .visible }
            let saved = persist()
            if saved { message = failed.isEmpty ? L("已恢复默认整理：图标均常驻，浮栏顺序已清除。") : L("部分图标未能显示，已保留这些图标的规则，请重试。") }
            busyID = nil; lastLayoutSignature = nil
            recordDiagnostic("resetArrangement", extra: ["saved": saved, "failedIDs": Array(failed)])
        }
    }

    func togglePause() {
        guard busyID == nil, !refreshing, !spacingApplying, !presentingShelf, temporaryNativeEntry == nil else { return }
        Task {
            await refresh(captureArtwork: false, cause: "pause-toggle")
            paused.toggle(); closeShelf()
            service.setCollapsed(!paused && accessibility)
        }
    }

    func toggleShelf() {
        let requestedAt = Date()
        Task { await toggleShelfWithCachedSnapshot(requestedAt: requestedAt) }
    }

    private func toggleShelfWithCachedSnapshot(preferPointer: Bool = false, requestedAt: Date = Date()) async {
        if shelfPresented { closeShelf(); return }
        guard busyID == nil, !spacingApplying, !presentingShelf else { return }
        if temporaryNativeEntry != nil {
            guard !service.nativeMenuOpen() else { return }
            await restoreTemporaryNativeEntry()
        }
        presentingShelf = true; defer { presentingShelf = false }
        // Classification is already shared by settings and the shelf. Never
        // put a cross-process scan, sorting repair or screenshot before opening.
        deferredShelfRefresh = deferredShelfRefresh || Date().timeIntervalSince(lastSnapshotRefresh) > 5
        pinned = false; outsideSince = nil
        let preferred = preferPointer ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) : nil
        shelfScreenNumber = preferred?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if shelfPanel == nil {
            let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = L("小屉浮栏")
            panel.animationBehavior = .none
            panel.level = .statusBar; panel.backgroundColor = .clear; panel.isOpaque = false
            panel.hasShadow = true; panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentView = NSHostingView(rootView: ShelfView().environmentObject(self))
            shelfPanel = panel
        }
        sizeShelf()
        shelfPanel?.makeKeyAndOrderFront(nil); shelfPresented = true
        shelfGeneration += 1
        let generation = shelfGeneration
        let orderedMilliseconds = Date().timeIntervalSince(requestedAt) * 1000
        let screen = currentShelfScreen, anchor = shelfAnchor
        let hidden = entries.filter { $0.canMove && $0.placement == .shelf }
        shelfArtworkTask?.cancel()
        shelfArtworkTask = Task { [weak self] in
            // Let AppKit present the cached panel before doing even optional
            // artwork work. A closed/reopened panel owns a different generation.
            await Task.yield()
            guard let self else { return }
            for _ in 0..<20 {
                guard !Task.isCancelled, self.shelfPresented, self.shelfGeneration == generation else { return }
                if self.shelfPanel?.occlusionState.contains(.visible) == true { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            self.recordDiagnostic("shelfOpen", extra: ["cachedSnapshot": true,
                "orderFrontMilliseconds": orderedMilliseconds,
                "visibleMilliseconds": Date().timeIntervalSince(requestedAt) * 1000,
                "panelPixelsVisible": self.shelfPanel?.occlusionState.contains(.visible) ?? false])
            guard !Task.isCancelled, self.shelfPresented, self.shelfGeneration == generation else { return }
            if let appearance = await self.service.captureMenuBarAppearance(screen: screen, anchor: anchor) {
                guard !Task.isCancelled, self.shelfPresented, self.shelfGeneration == generation else { return }
                self.shelfAppearance = appearance
            }
            let images = await self.service.capture(hidden, force: true)
            guard !Task.isCancelled, self.shelfPresented, self.shelfGeneration == generation else { return }
            let capturedIDs = Set(hidden.map(\.id))
            for index in self.entries.indices where capturedIDs.contains(self.entries[index].id) {
                if let image = images[self.entries[index].windowID] { self.entries[index].trayImage = image }
            }
            if !images.isEmpty { self.sizeShelf() }
        }
    }

    private var currentShelfScreen: NSScreen {
        if let number = shelfScreenNumber, let screen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == number }) { return screen }
        return NSScreen.screens.first(where: { $0.frame.intersects(service.entranceAnchor) }) ?? NSScreen.main!
    }
    private var shelfAnchor: CGRect {
        let screen = currentShelfScreen
        let real = service.entranceAnchor
        if screen.frame.intersects(real) { return real }
        return CGRect(x: min(max(NSEvent.mouseLocation.x, screen.frame.minX), screen.frame.maxX - 24),
                      y: screen.visibleFrame.maxY, width: 24, height: 0)
    }
    var shelfLayout: ShelfLayout {
        let hidden = accessibility ? entries.filter { $0.canMove && $0.placement == .shelf } : []
        return ShelfLayout(itemWidths: hidden.map(\.shelfWidth),
            itemHeight: hidden.map { $0.trayImage?.size.height ?? $0.frame.height }.max() ?? ShelfLayout.tileHeight,
            availableWidth: currentShelfScreen.frame.width - 20)
    }
    private func sizeShelf() {
        let layout = shelfLayout, screen = currentShelfScreen, anchor = shelfAnchor
        let x = min(max(anchor.maxX - layout.width, screen.frame.minX + 10), screen.frame.maxX - layout.width - 10)
        let y = max(screen.visibleFrame.minY + 10, min(anchor.minY - layout.height - 7, screen.visibleFrame.maxY - layout.height))
        shelfPanel?.setFrame(NSRect(x: x, y: y, width: layout.width, height: layout.height), display: true)
    }
    func closeShelf() {
        shelfGeneration += 1; shelfArtworkTask?.cancel(); shelfArtworkTask = nil
        shelfPanel?.orderOut(nil); shelfPresented = false; pinned = false; outsideSince = nil; shelfScreenNumber = nil
        shelfClosedAt = Date()
    }

    func activate(_ entry: MenuBarEntry, right: Bool = false, modifiers: NSEvent.ModifierFlags = []) {
        guard busyID == nil, !spacingApplying, temporaryNativeEntry == nil else { return }
        guard accessibility else { closeShelf(); message = ServiceError.permission.localizedDescription; showSettings(.permissions); return }
        busyID = entry.id
        closeShelf(); nativeActionUntil = Date().addingTimeInterval(0.5)
        Task {
            defer { busyID = nil }
            do {
                var active = entry
                if entry.placement == .shelf && !paused {
                    temporaryNativeEntry = entry
                    active = try await service.move(entry, to: .visible, collapseAfter: true)
                }
                var flags: CGEventFlags = []
                if modifiers.contains(.command) { flags.insert(.maskCommand) }
                if modifiers.contains(.shift) { flags.insert(.maskShift) }
                if modifiers.contains(.option) { flags.insert(.maskAlternate) }
                if modifiers.contains(.control) { flags.insert(.maskControl) }
                try await service.click(active, right: right, modifiers: flags); message = nil
                recordDiagnostic(right ? "rightClick" : "leftClick", entry: entry,
                    extra: ["temporaryItemOnly": temporaryNativeEntry != nil, "modifierFlags": modifiers.rawValue])
                if onboardingTrial == entry.id {
                    onboardingTrialAccessed = true; config.onboardingCompleted = true; persist()
                }
            } catch {
                recordDiagnostic(right ? "rightClickFailed" : "leftClickFailed", entry: entry,
                    extra: ["error": error.localizedDescription, "modifierFlags": modifiers.rawValue,
                            "movable": entry.canMove])
                message = error.localizedDescription
            }
            nativeActionUntil = Date().addingTimeInterval(0.5)
        }
    }

    private func restoreTemporaryNativeEntry() async {
        guard let original = temporaryNativeEntry, busyID == nil else { return }
        guard accessibility else {
            temporaryNativeEntry = nil; nativeActionUntil = nil; permissionRestorePending = true; return
        }
        busyID = original.id
        defer { busyID = nil; temporaryNativeEntry = nil; nativeActionUntil = nil; lastLayoutSignature = nil }
        do {
            var current = original; current.placement = .visible
            let restored = try await service.move(current, to: .shelf, collapseAfter: !paused && accessibility)
            if let i = entries.firstIndex(where: { $0.id == original.id }) { entries[i] = restored }
            recordDiagnostic("nativeItemRestored", entry: original)
        } catch {
            // A failed restoration must be honest about the actual visible item.
            if let i = entries.firstIndex(where: { $0.id == original.id }) { entries[i].placement = .visible }
            config.placements[original.id] = .visible; persist()
            message = L("未能重新收起 %@，已保留在菜单栏，可在图标整理中重试。", original.name)
            recordDiagnostic("nativeItemRestoreFailed", entry: original)
        }
    }

    private func installMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            Task { @MainActor in
                guard let self, self.busyID == nil, !self.spacingApplying, !self.refreshing else { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !self.presentingShelf else { return }
                if self.shelfPresented { self.deferredShelfRefresh = true; return }
                await self.refresh(captureArtwork: false, cause: "manual-drag")
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.shelfPresented, !self.pinned else { return }
                if let frame = self.shelfPanel?.frame, !frame.contains(NSEvent.mouseLocation) { self.closeShelf() }
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && self.matchesShortcut(event) { self.triggerShortcut(); return nil }
            if event.type == .keyDown && event.keyCode == 53 && self.shelfPresented { self.closeShelf(); return nil }
            if event.type != .keyDown && self.shelfPresented && !self.pinned,
               let frame = self.shelfPanel?.frame, !frame.contains(NSEvent.mouseLocation) { self.closeShelf() }
            return event
        }) { monitors.append(monitor) }
    }

    private func tick() {
        if Date().timeIntervalSince(lastPermissionCheck) > 2 { lastPermissionCheck = Date(); checkPermissions() }
        guard busyID == nil, !spacingApplying, !refreshing, !presentingShelf else { return }
        if temporaryNativeEntry == nil { service.updateNativeSystemAccess() }
        if deferredShelfRefresh, !shelfPresented, temporaryNativeEntry == nil, nativeActionUntil == nil,
           Date().timeIntervalSince(shelfClosedAt) > 0.75, NSEvent.pressedMouseButtons == 0 {
            deferredShelfRefresh = false
            Task {
                guard !self.shelfPresented, self.busyID == nil, !self.refreshing, self.temporaryNativeEntry == nil else {
                    self.deferredShelfRefresh = true; return
                }
                await self.refresh(captureArtwork: false, cause: "shelf-idle")
            }
            return
        }
        // Observe only stable, idle topology. Our own moves/native menu reveals
        // and a user's in-progress drag must never become a persisted category.
        if !shelfPresented, NSEvent.pressedMouseButtons == 0,
           Date().timeIntervalSince(lastLayoutCheck) > 2,
           nativeActionUntil == nil,
           !service.nativeMenuOpen() {
            lastLayoutCheck = Date()
            if let signature = service.layoutSignature(), signature != lastLayoutSignature {
                Task { await refresh(captureArtwork: false, cause: "layout-change") }
            }
        }
        if temporaryNativeEntry != nil, let grace = nativeActionUntil, Date() >= grace,
           !service.nativeMenuOpen(), NSEvent.pressedMouseButtons == 0 {
            Task { await restoreTemporaryNativeEntry() }; return
        }
        guard shelfPresented || nativeActionUntil != nil else { return }
        let pointer = NSEvent.mouseLocation
        let insidePanel = shelfPanel?.frame.insetBy(dx: -6, dy: -8).contains(pointer) == true && shelfPresented
        let insideBar = service.entranceAnchor.insetBy(dx: -8, dy: -12).contains(pointer)
        let holding = NSEvent.pressedMouseButtons != 0
        if insidePanel || insideBar || holding || pinned { outsideSince = nil; return }
        if let grace = nativeActionUntil, Date() < grace { return }
        if service.nativeMenuOpen() { outsideSince = nil; return }
        if outsideSince == nil { outsideSince = Date(); return }
        if LayoutPolicy.shouldCollapse(pinned: pinned, pointerInside: false, nativeMenuOpen: false,
                                       elapsed: Date().timeIntervalSince(outsideSince!), delay: config.collapseDelay) {
            closeShelf(); nativeActionUntil = nil
            if !paused && accessibility { service.setCollapsed(true) }
        }
    }

    func openPermission(_ screen: Bool) {
        let path = screen ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") { NSWorkspace.shared.open(url) }
    }
    func requestScreenPermission() { CGRequestScreenCaptureAccess(); checkPermissions() }
    func requestNativeOrderingAccess() {
        Task { if await service.requestNativeLayoutAccess() { await refresh(captureArtwork: false, cause: "layout-access") } }
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        guard config.shortcut != "none", shortcutNotice == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code: UInt16 = config.shortcut == "commandShiftB" ? UInt16(kVK_ANSI_B) : UInt16(kVK_Space)
        return modifiers == [.command, .shift] && event.keyCode == code && !event.isARepeat
    }

    private func triggerShortcut(source: String = "local-monitor") {
        guard Date().timeIntervalSince(lastShortcut) > 0.2 else { return }
        guard busyID == nil, !spacingApplying else { return }
        lastShortcut = Date()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        Task {
            await toggleShelfWithCachedSnapshot(preferPointer: true)
            try? await Task.sleep(nanoseconds: 60_000_000)
            recordDiagnostic("shortcut", extra: ["shortcutSource": source, "frontmostBundle": frontmost,
                                                  "panelVisible": shelfPanel?.isVisible ?? false,
                                                  "panelPixelsVisible": shelfPanel?.occlusionState.contains(.visible) ?? false])
        }
    }

    private func recordDiagnostic(_ action: String, entry: MenuBarEntry? = nil, extra: [String: Any] = [:]) {
        var result: [String: Any] = ["action": action, "date": ISO8601DateFormatter().string(from: Date()),
                                   "shelfPresented": shelfPresented,
                                   "nativeMenuObserved": service.lastNativeMenuObserved]
        result["bundle"] = entry?.bundleID
        result["moveMilliseconds"] = service.lastMoveMilliseconds
        result["cursorDisplacement"] = service.lastCursorDisplacement
        result["moveTrace"] = service.lastMoveTrace
        result["clickMechanism"] = service.lastClickMechanism
        result["nativeMenuItemCount"] = service.lastNativeMenuItemCount
        result["nativeMenuObserverAvailable"] = service.nativeMenuObserverAvailable
        result["entranceWidth"] = service.entranceAnchor.width
        result["entranceTemplate"] = service.entrance?.button?.image?.isTemplate ?? false
        result["dividerArtworkPresent"] = service.divider?.button?.image != nil
        result["spacingApplying"] = spacingApplying
        result["busy"] = busyID ?? ""
        result["keyboardRouting"] = "registered-hotkey-and-passive-monitor"
        result["temporaryNativeItem"] = temporaryNativeEntry?.id
        result["onboardingTrialAccessed"] = onboardingTrialAccessed
        for (key, value) in extra { result[key] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = store.url.deletingLastPathComponent().appendingPathComponent("last-check.json")
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if let compact = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let line = String(data: compact, encoding: .utf8) {
            let history = url.deletingLastPathComponent().appendingPathComponent("diagnostic-history.jsonl")
            var rows = (try? String(contentsOf: history, encoding: .utf8))?.split(separator: "\n").suffix(199).map(String.init) ?? []
            rows.append(line)
            try? (rows.joined(separator: "\n") + "\n").write(to: history, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history.path)
        }
    }

    func noteDrag(_ action: String, entryID: String) {
        recordDiagnostic(action, extra: ["entryID": entryID])
    }

    var spacingReloadTargets: [SpacingReloadTarget] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry.canMove, entry.pid != getpid(), seen.insert(entry.bundleID).inserted,
                  let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated,
                  let url = app.bundleURL else { return nil }
            return SpacingReloadTarget(bundleID: entry.bundleID, name: entry.name, pid: entry.pid, url: url)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func isSpacingReloadSelected(_ bundle: String) -> Bool {
        config.spacingReloadIsSelected(bundle)
    }
    func selectSpacingReload(_ bundle: String, selected: Bool) {
        var selection = Set(spacingReloadTargets.filter { isSpacingReloadSelected($0.bundleID) }.map(\.bundleID))
        if selected { selection.insert(bundle) } else { selection.remove(bundle) }
        config.spacingReloadSelection = selection.sorted(); persist()
    }
    func syncSpacingSnapshot() {
        currentSpacing = spacing.read(); selectedSpacing = currentSpacing.preset ?? .standard
    }

    func reopenSpacingApps() {
        guard !spacingApplying, !refreshing, busyID == nil, temporaryNativeEntry == nil else { return }
        let targets = spacingReloadTargets.filter { isSpacingReloadSelected($0.bundleID) }
        guard !targets.isEmpty else { spacingNotice = L("请选择需要重新打开的应用。"); return }
        let before = service.measuredWidths(entries)
        spacingApplying = true; closeShelf()
        Task {
            let result = await SpacingReloader.reopen(targets) { [weak self] name in
                self?.spacingNotice = L("正在重新打开 %@…", name)
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            spacingApplying = false
            await refresh()
            let after = service.measuredWidths(entries)
            service.setCollapsed(!paused && accessibility)
            if result.failures.isEmpty {
                spacingNotice = L("已重新打开 %ld 个应用以采用新间距。未选中的应用在下次打开后更新。", result.reopened.count)
            } else {
                spacingNotice = L("已重新打开 %ld 个应用。未完成：%@。未强制退出，请稍后重试。", result.reopened.count, result.failures.joined(separator: ", "))
            }
            recordDiagnostic("spacingReload", extra: ["reopened": result.reopened, "failures": result.failures,
                                                       "widthsBefore": before, "widthsAfter": after,
                                                       "configuredSpacing": currentSpacing.spacing as Any? ?? NSNull(),
                                                       "configuredPadding": currentSpacing.padding as Any? ?? NSNull()])
        }
    }

    func applySpacing(_ preset: SpacingPreset) {
        guard !spacingApplying, !refreshing, busyID == nil, temporaryNativeEntry == nil else { return }
        let original = spacing.read()
        let target = preset.values.map { SpacingSnapshot(spacing: $0.spacing, padding: $0.padding) } ?? SpacingSnapshot(spacing: nil, padding: nil)
        guard target != original else {
            currentSpacing = original; selectedSpacing = preset
            spacingNotice = L("当前已是 %@，没有重复修改或重开应用。", preset.title); return
        }
        var updated = config
        if updated.originalSpacing == nil { updated.originalSpacing = original }
        updated.pendingSpacingUndo = original
        do { try store.save(updated) } catch { spacingNotice = L("无法保存恢复备份，未修改系统设置。"); return }
        guard spacing.write(target) else {
            let rolledBack = spacing.write(original)
            spacingNotice = rolledBack ? L("写入未通过检查，已恢复修改前的值。") : L("写入或恢复失败，请保留配置备份并检查系统设置。")
            return
        }
        updated.lastSpacing = target
        do { try store.save(updated) }
        catch {
            let rolledBack = spacing.write(original)
            spacingNotice = rolledBack ? L("配置保存失败，已恢复修改前的系统间距。") : L("配置和系统间距恢复失败，请保留备份并重试。")
            return
        }
        config = updated; currentSpacing = target; selectedSpacing = preset
        refreshSpacingAppearance(label: preset.title)
    }
    private func refreshSpacingAppearance(label: String) {
        spacingNotice = L("已保存 · %@。已有图标在所属应用重新打开后更新。", label)
        recordDiagnostic("spacing", extra: ["pendingSessionReload": true,
            "configuredSpacing": currentSpacing.spacing as Any? ?? NSNull(),
            "configuredPadding": currentSpacing.padding as Any? ?? NSNull()])
        if config.reopenAppsForSpacing == true {
            if spacingReloadTargets.contains(where: { isSpacingReloadSelected($0.bundleID) }) { reopenSpacingApps() }
            else { spacingNotice = L("已保存 · %@。尚未选择可重开的应用；已有图标在所属应用下次打开后更新。", label) }
        }
    }
    func undoSpacing() {
        guard !spacingApplying, busyID == nil, !refreshing, let previous = config.pendingSpacingUndo else { return }
        let current = spacing.read()
        if let last = config.lastSpacing, current != last {
            spacingNotice = L("系统间距已被其他工具修改，为避免覆盖，请先确认当前设置。"); return
        }
        guard spacing.write(previous) else { spacingNotice = L("恢复未通过检查，请重试。"); return }
        var updated = config; updated.pendingSpacingUndo = nil; updated.lastSpacing = nil
        do { try store.save(updated) }
        catch {
            let restored = spacing.write(current)
            spacingNotice = restored ? L("撤销记录未能保存，系统间距已保持原值。") : L("撤销记录和间距恢复失败，请保留备份并重试。")
            return
        }
        config = updated; currentSpacing = previous; selectedSpacing = previous.preset ?? .standard
        refreshSpacingAppearance(label: L("已撤销修改"))
    }

    func registerShortcut() {
        let code: UInt32 = config.shortcut == "commandShiftB" ? UInt32(kVK_ANSI_B) : UInt32(kVK_Space)
        let ok = hotkey.register(code: code, enabled: config.shortcut != "none")
        shortcutNotice = ok ? nil : L("快捷键已被占用，未注册。请更换组合。")
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = L("请在系统设置的登录项中完成启用。") }
        } catch { message = L("登录时启动未能更新：%@", error.localizedDescription) }
    }
    func finishOnboarding() {
        onboardingTrial = nil; onboardingTrialAccessed = false
        onboarding = false; config.onboardingCompleted = true; persist(); page = .items; resizeSettingsWindow()
    }

    func beginOnboardingTrial(_ entry: MenuBarEntry) {
        let ready = { [weak self] in
            guard let self else { return }
            self.onboardingTrial = entry.id; self.onboardingTrialAccessed = false; self.message = nil
        }
        if entry.placement == .shelf { ready() }
        else { setPlacement(entry, .shelf, onSuccess: ready) }
    }

}

// Register only the chosen shortcut. An intercepting session keyboard tap is
// intentionally absent: ordinary typing must never pass through our callback.
final class HotkeyManager {
    var onPress: ((String) -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, data in
            guard let data else { return noErr }
            let owner = Unmanaged<HotkeyManager>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { owner.onPress?("carbon") }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(code: UInt32, enabled: Bool) -> Bool {
        unregister(); guard enabled else { return true }
        let id = EventHotKeyID(signature: 0x4D425354, id: 1)
        return RegisterEventHotKey(code, UInt32(cmdKey | shiftKey), id, GetEventDispatcherTarget(), 0, &reference) == noErr
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
    }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
}
