import Foundation
import CoreGraphics
import MenuBarCore

// Standalone checks also run on a Mac with Command Line Tools and no XCTest bundle.
@main
enum CoreChecks {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: \(message)") }
    }
    static func main() throws {
        let nativeAllowed = NativeVisibilityPolicy.allowedBundles(
            running: ["org.example.hidden", "org.example.visible", "com.apple.controlcenter", "local.menubarstudio.app"],
            hidden: ["org.example.hidden", "com.apple.controlcenter", "local.menubarstudio.app"],
            ownBundle: "local.menubarstudio.app")
        expect(!nativeAllowed.contains("org.example.hidden"), "native allow-list excludes the requested hidden app")
        expect(nativeAllowed.isSuperset(of: ["org.example.visible", "com.apple.controlcenter", "local.menubarstudio.app"]),
               "native allow-list preserves other apps, system agents and the recovery entrance")
        expect(NativeVisibilityPolicy.allowedBundles(running: ["org.example.new"], hidden: [], ownBundle: "local.menubarstudio.app")
            .contains("org.example.new"), "new applications stay visible by default")
        print("PASS macOS 27 native allow-list and protected recovery entrance")
        let nativeRow = [CGRect(x: 100, y: 0, width: 26, height: 24),
                         CGRect(x: 126, y: 0, width: 82, height: 24),
                         CGRect(x: 100, y: 900, width: 26, height: 24)]
        expect(!NativeVisibilityPolicy.hasOverlappingItems(nativeRow),
            "native rows permit adjacent wide items and separate displays")
        expect(NativeVisibilityPolicy.hasOverlappingItems(nativeRow + [CGRect(x: 120, y: 0, width: 26, height: 24)]),
            "a rendered native icon overlapping a neighbour is not accepted")
        print("PASS native rendered-slot overlap checks")
        let ownKey = "status:local.menubarstudio.app::MenuBarStudio.Entrance"
        let legacyOwnKey = "status:MenuBarStudio::MenuBarStudio.Entrance"
        let entranceMigration = NativeBarOrderPolicy.entranceBootstrap(positions: [legacyOwnKey: 378],
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio"], fallbackPosition: 1472)
        expect(entranceMigration == [ownKey: 1472], "upgrade creates the canonical host identity without rewriting the old alias")
        expect(NativeBarOrderPolicy.entranceKey(positions: [legacyOwnKey: 378].merging(entranceMigration, uniquingKeysWith: { _, new in new }),
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio"]) == ownKey,
            "fresh canonical identity takes precedence without a user's manual drag")
        expect(NativeBarOrderPolicy.entranceBootstrap(positions: [ownKey: 475], preferredOwner: "local.menubarstudio.app",
            alternateOwners: ["MenuBarStudio"], fallbackPosition: 1472).isEmpty, "existing native positions are not reset at every launch")
        expect(NativeBarOrderPolicy.entranceKey(positions: [legacyOwnKey: 378],
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio", "小屉"]) == legacyOwnKey,
            "an upgraded executable-name entrance remains addressable")
        expect(NativeBarOrderPolicy.entranceKey(positions: [ownKey: 475, legacyOwnKey: 378],
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio"]) == ownKey,
            "the exact bundle owner takes priority over a legacy alias")
        expect(NativeBarOrderPolicy.entranceKey(positions: ["status:org.unrelated::MenuBarStudio.Entrance": 475],
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio"]) == nil,
            "another app's matching item name is never rewritten")
        expect(NativeBarOrderPolicy.entranceKey(positions: [legacyOwnKey: 378, "status:小屉::MenuBarStudio.Entrance": 400],
            preferredOwner: "local.menubarstudio.app", alternateOwners: ["MenuBarStudio", "小屉"]) == nil,
            "ambiguous legacy owners fail closed instead of changing an arbitrary entry")
        let aKey = "status:org.example.a::Item-0"
        let bKey = "status:org.example.b::Item-0"
        let legacyItem = "status:Probe::DrawerBar.NativeSmokeProbe"
        let canonicalItem = "status:local.drawerbar.probe::DrawerBar.NativeSmokeProbe"
        let itemMigration = NativeBarOrderPolicy.itemBootstrap(positions: [legacyItem: 500.5, bKey: 228],
            preferredOwner: "local.drawerbar.probe", alternateOwners: ["Probe"])
        expect(itemMigration == [canonicalItem: 500.5], "imported source aliases create only their canonical native item key")
        expect(NativeBarOrderPolicy.itemBootstrap(positions: [legacyItem: 500.5, canonicalItem: 600],
            preferredOwner: "local.drawerbar.probe", alternateOwners: ["Probe"]).isEmpty,
            "existing source ordering takes precedence over an old alias")
        expect(NativeBarOrderPolicy.itemBootstrap(positions: [legacyItem: 500.5, "status:OldProbe::DrawerBar.NativeSmokeProbe": 600],
            preferredOwner: "local.drawerbar.probe", alternateOwners: ["Probe", "OldProbe"]).isEmpty,
            "conflicting source identities fail closed instead of arbitrarily picking a position")
        let positionTable = [ownKey: 475.0, aKey: 342.0, bKey: 228.0,
            "status:org.stopped::Item-0": 99999.0, "module:AudioVideoModule": 9000.0, "module:WiFi": 206.0]
        let liveOwners: Set<String> = ["local.menubarstudio.app", "org.example.a", "org.example.b"]
        expect(NativeBarOrderPolicy.pinEntrance(positions: positionTable, entrance: ownKey, activeOwners: liveOwners) == [:],
            "stopped apps and the protected privacy indicator do not displace the entrance")
        let insertion = NativeBarOrderPolicy.insertAfterEntrance(positions: positionTable, entrance: ownKey,
            targets: [bKey], activeOwners: liveOwners, visibleOwners: ["org.example.a"])!
        expect(insertion[bKey]! < positionTable[ownKey]! && insertion[bKey]! > positionTable[aKey]!,
            "shown item is inserted between entrance and the first remaining item")
        expect(insertion[aKey] == nil && insertion["module:WiFi"] == nil,
            "insertion never rewrites peer or system weights")
        var newlyDisplaced = positionTable
        newlyDisplaced["status:org.new::Item-0"] = 600
        let repin = NativeBarOrderPolicy.pinEntrance(positions: newlyDisplaced, entrance: ownKey,
            activeOwners: liveOwners.union(["org.new"]))!
        expect(repin[ownKey]! > 600 && repin.count == 1, "new live icons leave entrance pinned left without changing peers")
        let multi = NativeBarOrderPolicy.insertAfterEntrance(positions: positionTable.merging(
            ["status:org.example.b::Second": 227.0], uniquingKeysWith: { _, value in value }), entrance: ownKey,
            targets: [bKey, "status:org.example.b::Second"], activeOwners: liveOwners, visibleOwners: ["org.example.a"])!
        expect(multi[bKey]! > multi["status:org.example.b::Second"]! && multi["status:org.example.b::Second"]! > 342,
            "all icons of the incoming app form one ordered block immediately after entrance")
        let arrowBox = CGRect(x: 100, y: 0, width: 26, height: 24)
        let adjacent = CGRect(x: 126, y: 0, width: 96, height: 24)
        expect(NativeBarOrderPolicy.isImmediateRight(entrance: arrowBox, target: adjacent,
            peers: [CGRect(x: 222, y: 0, width: 24, height: 24)]), "wide shown icon occupies the next slot")
        expect(!NativeBarOrderPolicy.isImmediateRight(entrance: arrowBox,
            target: CGRect(x: 250, y: 0, width: 24, height: 24), peers: [adjacent]), "a visible peer before the target fails verification")
        expect(!NativeBarOrderPolicy.isLeading(entrance: arrowBox,
            peers: [CGRect(x: 60, y: 0, width: 24, height: 24)]), "a peer left of the entrance fails verification")
        let liveTable = [ownKey: 428.5, legacyOwnKey: 518.5,
                         "status:net.domzilla.caffeine::Item-0": 454.5,
                         "module:AudioVideoModule": 480.5, bKey: 282.5]
        let liveInsertion = NativeBarOrderPolicy.insertAfterEntrance(positions: liveTable, entrance: ownKey,
            targets: [bKey], activeOwners: ["local.menubarstudio.app", "net.domzilla.caffeine", "org.example.b"],
            visibleOwners: ["net.domzilla.caffeine"])!
        expect(liveInsertion[ownKey] == 486.5 && liveInsertion[bKey] == 483.5,
            "live canonical identity and newly persisted peers place the target before the privacy slot")
        expect(liveInsertion[legacyOwnKey] == nil && liveInsertion["module:AudioVideoModule"] == nil,
            "stale self aliases and protected indicators are never rewritten")
        expect(!NativeBarOrderPolicy.isImmediateRight(entrance: arrowBox,
            target: CGRect(x: 174, y: 0, width: 26, height: 24), peers: []),
            "a system-sized gap is not falsely accepted as adjacent insertion")
        print("PASS macOS 27 entrance pinning, adjacent insertion, wide items and peer preservation")
        expect(L10n.text("小屉", language: "en") == "DrawerBar", "English brand comes from packaged resources")
        expect(L10n.text("小屉", language: "zh-Hans") == "小屉", "Chinese brand remains unchanged")
        expect(L10n.text("屏幕录制 · 可选", language: "en") == "Screen Recording · Optional", "permission explanation is localized")
        let formatted = String(format: L10n.text("未能恢复 %@ 的位置：%@", language: "en"), "Example", "Unavailable")
        expect(formatted == "Could not restore Example: Unavailable", "formatted names and errors survive translation")
        expect(L10n.text("untranslated-debug-key", language: "en") == "untranslated-debug-key", "missing keys remain diagnosable")
        print("PASS English and Chinese resources, brand, permissions and format arguments (active: \(L10n.language))")
        expect(LayoutPolicy.windowID(from: -1) == nil, "hosted status window placeholder must not trap")
        expect(LayoutPolicy.windowID(from: 0) == nil, "zero window number is not an owned window")
        expect(LayoutPolicy.windowID(from: Int.max) == nil, "oversized window number must not trap")
        expect(LayoutPolicy.windowID(from: 42) == 42, "normal window number converts exactly")
        print("PASS macOS 26 hosted-window placeholders")
        expect(LayoutPolicy.itemID(bundle: "org.test.Flux", ordinal: 0, previousID: "com.apple.controlcenter#4") == "org.test.Flux#0", "host identity must not survive source resolution")
        expect(LayoutPolicy.itemID(bundle: "org.test.Flux", ordinal: 1, previousID: "org.test.Flux#0") == "org.test.Flux#0", "known application identity survives window reordering")
        expect(LayoutPolicy.itemID(bundle: "org.test.Other", ordinal: 0, previousID: "org.test.Flux#0") == "org.test.Other#0", "window reuse cannot inherit another application identity")
        print("PASS stable source identity instead of Control Center host IDs")
        expect(LayoutPolicy.prefersDarkIconBackdrop(red: 1, green: 1, blue: 1), "white menu glyphs need a dark backdrop")
        expect(!LayoutPolicy.prefersDarkIconBackdrop(red: 0, green: 0, blue: 0), "black menu glyphs need a light backdrop")
        expect(!LayoutPolicy.prefersDarkIconBackdrop(red: 0.15, green: 0.25, blue: 0.4), "dark colored artwork retains a light backdrop")
        print("PASS light and dark tray artwork contrast choices")
        let divider = CGRect(x: 273, y: 0, width: 20, height: 26)
        expect(LayoutPolicy.observedPlacement(item: CGRect(x: 218, y: 0, width: 30, height: 26), divider: divider) == .shelf,
               "reported ChatGPT left of divider must belong to the shelf despite an old visible rule")
        expect(LayoutPolicy.observedPlacement(item: CGRect(x: 307, y: 0, width: 30, height: 26), divider: divider) == .visible,
               "items right of divider stay visible")
        expect(LayoutPolicy.observedPlacement(item: CGRect(x: 270, y: 0, width: 30, height: 26), divider: divider) == nil,
               "overlapping frames during a move cannot overwrite a saved rule")
        expect(LayoutPolicy.observedPlacement(item: CGRect(x: 218, y: 0, width: 30, height: 26),
                divider: CGRect(x: -9707, y: 0, width: 10000, height: 26)) == nil,
               "old expanded coordinates cannot classify an item inside the stretched hidden divider")
        print("PASS observed placement and transitional-frame regression")

        let edge = CGRect(x: 500, y: 0, width: 16, height: 26)
        let arrow = CGRect(x: 516, y: 0, width: 26, height: 26)
        let visibleItem = CGRect(x: 542, y: 0, width: 24, height: 26)
        expect(LayoutPolicy.placementDestination(.visible, divider: edge, entrance: arrow, y: 13).x == 546,
               "newly shown items insert after the arrow rather than between the divider and arrow")
        expect(LayoutPolicy.placementDestination(.shelf, divider: edge, entrance: arrow, y: 13).x == 496,
               "hidden items move to the left of the divider")
        expect(LayoutPolicy.entranceIsLeading(divider: edge, entrance: arrow, otherItems: [visibleItem]),
               "arrow remains first in the visible section")
        expect(!LayoutPolicy.entranceIsLeading(divider: edge, entrance: CGRect(x: 600, y: 0, width: 26, height: 26), otherItems: [visibleItem]),
               "legacy visible icons left of the arrow require a one-time repair")
        expect(LayoutPolicy.entranceIsLeading(divider: CGRect(x: -9484, y: 0, width: 10000, height: 26), entrance: arrow, otherItems: [visibleItem]),
               "leading-arrow validation also works while hidden items are collapsed")
        print("PASS leading entrance and first visible insertion slot")

        let input = CGRect(x: 570, y: 0, width: 26, height: 26)
        let battery = CGRect(x: 596, y: 0, width: 38, height: 26)
        let misplacedMeter = CGRect(x: 634, y: 0, width: 82, height: 26)
        expect(!LayoutPolicy.isFirstVisibleSlot(item: misplacedMeter, entrance: arrow, otherItems: [input, battery]),
               "a sole visible SSRUN after Input and Battery must not pass first-slot verification")
        expect(LayoutPolicy.crossesProtectedItems(item: misplacedMeter, protectedItems: [input, battery]),
               "an unchanged visible classification must still detect crossing the protected group")
        expect(LayoutPolicy.isFirstVisibleSlot(item: visibleItem, entrance: arrow, otherItems: [input, battery]),
               "insertion before the first system anchor is valid with no other managed app")
        expect(!LayoutPolicy.crossesProtectedItems(item: visibleItem, protectedItems: [input, battery]),
               "ordinary managed placement before the protected group needs no repair")
        expect(!LayoutPolicy.isFirstVisibleSlot(item: misplacedMeter, entrance: arrow, otherItems: [visibleItem, input]),
               "another managed icon also occupies the first slot")
        expect(!LayoutPolicy.crossesProtectedItems(item: visibleItem,
                protectedItems: [CGRect(x: 400, y: 1000, width: 26, height: 26)]),
               "a protected item in another menu bar row cannot cause a repair")
        expect(!LayoutPolicy.isFirstVisibleSlot(item: CGRect(x: 400, y: 0, width: 26, height: 26), entrance: arrow, otherItems: []),
               "an item left of the entrance is never a valid shown insertion")
        print("PASS read-only system boundary and sole visible traffic-meter regression")
        expect(!LayoutPolicy.participatesInStatusOrdering(windowName: "AudioVideoModule", hostBundleID: "com.apple.controlcenter"),
               "the OS capture indicator must never be moved or mistaken for an app/system insertion slot")
        expect(LayoutPolicy.participatesInStatusOrdering(windowName: "Battery", hostBundleID: "com.apple.controlcenter"),
               "Battery remains a read-only ordering anchor")
        expect(LayoutPolicy.participatesInStatusOrdering(windowName: "Item-0", hostBundleID: "com.apple.controlcenter"),
               "unnamed hosted items must not all be excluded with the privacy indicator")
        expect(LayoutPolicy.participatesInStatusOrdering(windowName: "AudioVideoModule", hostBundleID: "org.example.app"),
               "a third-party title alone cannot claim the system privacy exception")

        let oneIcon = ShelfLayout(itemCount: 1, availableWidth: 1420)
        expect(oneIcon.viewportWidth == 26 && !oneIcon.needsHorizontalScrolling, "single native icon keeps its complete width and border insets")
        let sixIcons = ShelfLayout(itemCount: 6, availableWidth: 1420)
        expect(sixIcons.viewportWidth == 156 && !sixIcons.needsHorizontalScrolling, "all six hidden icons fit in one row without a scroll container")
        let longRow = ShelfLayout(itemWidths: Array(repeating: 82, count: 13), availableWidth: 1420)
        expect(longRow.width > 620 && longRow.width < 1420 && longRow.height == oneIcon.height && !longRow.needsHorizontalScrolling, "single row can grow beyond the old 620-point cap")
        let screenLimited = ShelfLayout(itemWidths: Array(repeating: 82, count: 30), availableWidth: 1000)
        expect(screenLimited.width == 1000 && screenLimited.needsHorizontalScrolling && screenLimited.height == oneIcon.height, "physical screen overflow remains a single accessible horizontal row")
        expect(ShelfLayout(itemCount: 0, availableWidth: 1420).width == 240, "empty state keeps enough room for its message")
        let nativeMeter = ShelfLayout(itemWidths: [19, 42, 82], itemHeight: 30, availableWidth: 1420)
        expect(nativeMeter.viewportWidth == 149 && nativeMeter.height == 44 && !nativeMeter.needsHorizontalScrolling,
               "native menu icon sizes and a wide SSRUN traffic meter remain unscaled in a compact single row")
        print("PASS shelf sizing, full first icon, all-hidden single row and screen limits")

        let absent = SpacingSnapshot(spacing: nil, padding: nil)
        let zero = SpacingSnapshot(spacing: 0, padding: 0)
        expect(absent != zero, "missing override differs from zero")
        let roundTrip = try JSONDecoder().decode(SpacingSnapshot.self, from: JSONEncoder().encode(absent))
        expect(roundTrip == absent && absent.preset == .standard && zero.preset == nil, "absent overrides survive restoration")
        expect(SpacingSnapshot(spacing: 17, padding: 3).preset == nil, "custom system values are not called default")
        expect(SpacingSnapshot(spacing: 12, padding: nil).preset == nil, "partial override is preserved")
        print("PASS spacing snapshot preservation and preset recognition")

        var config = UserConfiguration()
        config.placements["test#0"] = .shelf
        config.pendingSpacingUndo = SpacingSnapshot(spacing: nil, padding: 7)
        let saved = try JSONDecoder().decode(UserConfiguration.self, from: JSONEncoder().encode(config))
        expect(saved.placement(for: "test#0") == .shelf && saved.placement(for: "new#0") == .visible, "new items stay visible")
        expect(saved.pendingSpacingUndo?.padding == 7 && saved.pendingSpacingUndo?.spacing == nil, "undo preserves mixed missing values")
        print("PASS persisted placement rules and undo data")
        let legacy = Data(#"{"schemaVersion":1,"placements":{},"order":[],"collapseDelay":1.5,"shortcut":"commandShiftSpace","onboardingCompleted":true}"#.utf8)
        let migrated = try JSONDecoder().decode(UserConfiguration.self, from: legacy)
        expect(migrated.onboardingCompleted && migrated.identityVersion == nil, "old configuration remains readable before identity migration")
        print("PASS backward-compatible configuration migration")

        expect(!LayoutPolicy.shouldCollapse(pinned: true, pointerInside: false, nativeMenuOpen: false, elapsed: 100, delay: 1), "fixed shelf stays open")
        expect(!LayoutPolicy.shouldCollapse(pinned: false, pointerInside: false, nativeMenuOpen: true, elapsed: 100, delay: 1), "native menu interaction is not interrupted")
        expect(!LayoutPolicy.shouldCollapse(pinned: false, pointerInside: true, nativeMenuOpen: false, elapsed: 100, delay: 1), "pointer inside cancels collapse")
        expect(!LayoutPolicy.shouldCollapse(pinned: false, pointerInside: false, nativeMenuOpen: false, elapsed: 0.5, delay: 1), "delay is honored")
        expect(LayoutPolicy.shouldCollapse(pinned: false, pointerInside: false, nativeMenuOpen: false, elapsed: 1.1, delay: 1), "idle shelf closes")
        print("PASS collapse safeguards")

        expect(LayoutPolicy.sorted(["new1", "b", "a", "new2"], order: ["a", "b"]) == ["a", "b", "new1", "new2"], "new item ordering remains stable")
        expect(LayoutPolicy.sorted(["a", "b"], order: ["b", "b"]) == ["b", "a"], "duplicate saved IDs are tolerated")
        expect(LayoutPolicy.sorted(["chat#0", "other#0", "chat#0"], order: []) == ["chat#0", "other#0"], "hosted window replacement cannot duplicate a shelf item")
        expect(LayoutPolicy.sorted(["chat#0", "chat#1", "chat#0"], order: ["chat#1"]) == ["chat#1", "chat#0"], "distinct items from the same app remain available")
        print("PASS stable ordering and unique identities during hosted replacement")
        expect(LayoutPolicy.reordered(["a", "b", "c"], moving: "c", before: "a") == ["c", "a", "b"], "drop over first shelf tile changes ordering")
        expect(LayoutPolicy.reordered(["a", "b", "c"], moving: "a", before: nil) == ["b", "c", "a"], "background drop appends to shelf")
        expect(LayoutPolicy.reordered(["a", "b", "c"], moving: "b", before: "b") == ["a", "b", "c"], "drop on itself is a no-op")
        expect(LayoutPolicy.reordered(["a", "b", "c"], moving: "missing", before: "a") == ["a", "b", "c"], "foreign drag cannot add an item")
        expect(LayoutPolicy.reordered(["a", "b", "c"], moving: "a", before: "missing") == ["a", "b", "c"], "stale target cannot discard or reorder items")
        print("PASS shelf drag insertion, append, self-drop and stale identities")
        var relaunchConfig = UserConfiguration()
        expect(!relaunchConfig.spacingReloadIsSelected("new-app"), "fresh setup never preselects another app for relaunch")
        relaunchConfig.spacingReloadExclusions = ["excluded"]
        expect(relaunchConfig.spacingReloadIsSelected("previously-allowed") && !relaunchConfig.spacingReloadIsSelected("excluded"), "legacy relaunch choices remain readable")
        relaunchConfig.spacingReloadSelection = ["explicitly-selected"]
        expect(relaunchConfig.spacingReloadIsSelected("explicitly-selected") && !relaunchConfig.spacingReloadIsSelected("new-app"), "explicit selection does not expand to newly discovered apps")
        print("PASS explicit relaunch consent and legacy selection migration")
        let hiddenTopology = LayoutPolicy.statusTopologySignature(observed: [11: .visible], hiddenWindows: [12])
        expect(hiddenTopology == LayoutPolicy.statusTopologySignature(observed: [12: .shelf, 11: .visible], hiddenWindows: [12]),
               "an omitted hidden native window must not trigger another full layout scan")
        expect(hiddenTopology != LayoutPolicy.statusTopologySignature(observed: [11: .visible, 12: .visible], hiddenWindows: [12]),
               "a real manual move out of the hidden zone remains detectable")
        expect(hiddenTopology != LayoutPolicy.statusTopologySignature(observed: [:], hiddenWindows: [12]),
               "a missing visible window still changes the topology")
        expect(hiddenTopology != LayoutPolicy.statusTopologySignature(observed: [11: .visible, 13: .visible], hiddenWindows: [12]),
               "a newly discovered window still changes the topology")
        print("PASS hidden-window omission stability and real topology change detection")
        expect(MovementPolicy.usesWindowServerRoute(macOSMajorVersion: 26, hostBundleID: "com.apple.controlcenter"),
               "macOS 26 hosted status moves use one WindowServer route")
        expect(!MovementPolicy.usesWindowServerRoute(macOSMajorVersion: 26, hostBundleID: "org.example.app"),
               "app-owned status windows retain their existing handshake")
        expect(!MovementPolicy.usesWindowServerRoute(macOSMajorVersion: 25, hostBundleID: "com.apple.controlcenter"),
               "the new delivery path does not change older OS behavior")
        expect(!MovementPolicy.usesWindowServerRoute(macOSMajorVersion: 27, hostBundleID: "com.apple.controlcenter"),
               "an unverified newer menu bar architecture does not inherit the route")
        expect(MovementPolicy.insertionX(beforeNeighbor: 1000, sourceWidth: 82, sourceIsHidden: true,
                pickupAtLeftEdge: true) == 999, "left pickup must not subtract the wide source again and drop before the entrance")
        expect(MovementPolicy.insertionX(beforeNeighbor: 1000, sourceWidth: 26, sourceIsHidden: false,
                pickupAtLeftEdge: true) == 999, "visible-item repair uses the current first neighbor")
        expect(MovementPolicy.insertionX(beforeNeighbor: 1000, sourceWidth: 82, sourceIsHidden: true,
                pickupAtLeftEdge: false) == 917, "the existing right-pickup path retains its source-width adjustment")
        print("PASS native event route compatibility boundaries")
        var confirmation = MovementVerification()
        expect(!confirmation.observe(valid: true), "one valid frame is insufficient")
        expect(!confirmation.shouldRetry(deadlinePassed: true), "a late valid frame must get confirmation instead of another drag")
        expect(confirmation.observe(valid: true), "two consecutive valid frames confirm placement")
        var transient = MovementVerification()
        expect(!transient.observe(valid: true) && !transient.observe(valid: false), "an invalid frame resets confirmation")
        expect(transient.shouldRetry(deadlinePassed: true), "an unconfirmed wrong layout may retry after its deadline")
        expect(!transient.shouldRetry(deadlinePassed: false), "keep observing within the deadline")
        print("PASS late-frame confirmation without redundant native replay")
        let hostedEntrance = CGRect(x: 900, y: 0, width: 26, height: 26)
        expect(MovementPolicy.entranceArtworkIsClear(item: CGRect(x: 921, y: 0, width: 82, height: 26), entrance: hostedEntrance),
               "native hit padding cannot replay a correctly inserted traffic meter")
        expect(!MovementPolicy.entranceArtworkIsClear(item: CGRect(x: 919, y: 0, width: 82, height: 26), entrance: hostedEntrance),
               "actual drawer artwork collision still fails verification")
        print("PASS native hit padding and actual drawer artwork collision")

        let diagnosticsFixture: [String: Any] = [
            "icons": [["id": "org.example.app#0", "x": 123.5]],
            "nested": ["securityScopedBookmark": "DO-NOT-EXPORT", "accessToken": "DO-NOT-EXPORT", "path": "/Users/private-person/Library/test"],
            "binary": Data([1, 2, 3]), "number": Double.infinity,
            "error": "Failed at /Users/private-person/Library/test"
        ]
        let safeDiagnostics = DiagnosticsPrivacy.sanitize(diagnosticsFixture, home: "/Users/private-person")
        let safeBytes = try JSONSerialization.data(withJSONObject: safeDiagnostics)
        let safeText = String(decoding: safeBytes, as: UTF8.self)
        expect(!safeText.contains("DO-NOT-EXPORT") && !safeText.contains("private-person"), "diagnostics remove nested credentials and home usernames")
        expect(safeText.contains("org.example.app#0") && safeText.contains("123.5"), "diagnostics retain useful icon identity and geometry")
        expect(safeText.contains("omitted-data"), "diagnostics omit arbitrary binary data")
        print("PASS diagnostic privacy filtering, bounded values and JSON-safe geometry")

        let diagnosticTemp = FileManager.default.temporaryDirectory.appendingPathComponent("DrawerBar-ArchiveCheck-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: diagnosticTemp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: diagnosticTemp) }
        let support = diagnosticTemp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        try Data("DO-NOT-EXPORT".utf8).write(to: support.appendingPathComponent("configuration.json"))
        try FileManager.default.createSymbolicLink(at: support.appendingPathComponent("last-check.json"), withDestinationURL: support.appendingPathComponent("configuration.json"))
        let failure: [String: Any] = ["action": "placement", "verified": false, "requestedPlacement": "visible", "failure": ["errorType": "nativeLayoutUnconfirmed"], "bookmark": "DO-NOT-EXPORT"]
        try JSONSerialization.data(withJSONObject: failure).write(to: support.appendingPathComponent("last-failure.json"))
        let failedLine = String(decoding: try JSONSerialization.data(withJSONObject: failure), as: UTF8.self)
        try (failedLine + "\nmalformed\n{\"action\":\"layoutSync\"}\n").write(to: support.appendingPathComponent("diagnostic-history.jsonl"), atomically: true, encoding: .utf8)
        let zip = diagnosticTemp.appendingPathComponent("diagnostics.zip")
        try DiagnosticArchive.write(context: safeBytes, support: support, destination: zip)
        let listZip = Process(); let zipNamesPipe = Pipe()
        listZip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); listZip.arguments = ["-Z1", zip.path]
        listZip.standardOutput = zipNamesPipe; try listZip.run()
        let zipNamesBytes = zipNamesPipe.fileHandleForReading.readDataToEndOfFile(); listZip.waitUntilExit()
        let zipNames = Set(String(decoding: zipNamesBytes, as: UTF8.self).split(separator: "\n").map(String.init))
        expect(listZip.terminationStatus == 0 && zipNames == ["DrawerBar-Diagnostics/", "DrawerBar-Diagnostics/report.json", "DrawerBar-Diagnostics/READ-ME.txt"], "raw ZIP excludes resource forks, extended metadata and every undeclared file")
        let unpack = diagnosticTemp.appendingPathComponent("unpacked")
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, unpack.path]; try unzip.run(); unzip.waitUntilExit()
        expect(unzip.terminationStatus == 0, "diagnostic ZIP can actually be extracted")
        let exportedFolder = unpack.appendingPathComponent("DrawerBar-Diagnostics")
        let exportedNames = Set(try FileManager.default.contentsOfDirectory(atPath: exportedFolder.path))
        expect(exportedNames == ["report.json", "READ-ME.txt"], "archive contains only the two declared files")
        let reportData = try Data(contentsOf: exportedFolder.appendingPathComponent("report.json"))
        let report = try JSONSerialization.jsonObject(with: reportData) as! [String: Any]
        let exportedFailure = report["lastFailedOperation"] as? [String: Any]
        expect(exportedFailure?["requestedPlacement"] as? String == "visible", "last failed show survives a later layout scan")
        expect(!String(decoding: reportData, as: UTF8.self).contains("DO-NOT-EXPORT"), "raw configuration and credentials never enter the ZIP")
        expect((report["readWarnings"] as? [String])?.count == 2, "unsafe files and malformed history are reported, not silently trusted")
        let attributes = try FileManager.default.attributesOfItem(atPath: zip.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "export archive is private to the current user")
        print("PASS real diagnostic ZIP, failure retention, log corruption, symlink exclusion and private output")

        print("All core checks passed. No system settings were written.")
    }
}
