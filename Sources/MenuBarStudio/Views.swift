import SwiftUI
import AppKit
import MenuBarCore

private let accent = Color.accentColor
private let secondaryText = Color(nsColor: .labelColor).opacity(0.72)

struct RootView: View {
    @EnvironmentObject var model: AppController
    var body: some View {
        Group {
            if model.onboarding { OnboardingView() }
            else {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(L("小屉")).font(.system(size: 13, weight: .medium)).foregroundStyle(secondaryText)
                            Spacer()
                            if model.refreshing { ProgressView().controlSize(.small) }
                            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).help(L("刷新实际菜单栏项目"))
                        }.padding(.horizontal, 30).frame(height: 46)
                        Divider()
                        if let message = model.message { NoticeView(text: message) { model.message = nil }.padding(.horizontal, 30).padding(.top, 16) }
                        ScrollView {
                            Group {
                                switch model.page {
                                case .items: ItemsView()
                                case .appearance: AppearanceView()
                                case .general: GeneralView()
                                case .permissions: PermissionsView()
                                }
                            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                        }.id(model.page)
                    }.background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: model.onboarding ? 620 : 880, minHeight: model.onboarding ? 690 : 620)
        .tint(.blue)
        .font(.system(size: 14))
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(SettingsPage.allCases) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.symbol).font(.system(size: 19)).frame(width: 26)
                        Text(page.title).font(.system(size: 15, weight: model.page == page ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13).frame(height: 46)
                    .foregroundStyle(model.page == page ? Color.blue : Color.primary)
                    .background(model.page == page ? Color.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            Text((L10n.appName + "  0.1.10")).font(.system(size: 11)).foregroundStyle(secondaryText).padding(12)
        }.padding(.horizontal, 12).padding(.top, 44).frame(width: 250).background(.regularMaterial)
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 25)
    }
}

struct NoticeView: View {
    let text: String
    var dismiss: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.blue)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss { Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(secondaryText) }
        }.padding(12).background(Color.blue.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AppIcon: View {
    let entry: MenuBarEntry
    var size: CGFloat = 36
    var tray = false
    var body: some View {
        Group {
            if let image = tray ? (entry.trayImage ?? entry.icon) : entry.icon {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else { Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(secondaryText) }
        }.frame(width: size, height: size)
    }
}

struct ItemsView: View {
    @EnvironmentObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: L("整理你的菜单栏"), subtitle: L("点击图标切换收起或显示，也可以拖到另一区域。"))
                .padding(.bottom, -18)
            if !model.accessibility {
                HStack {
                    Label(L("开启辅助功能后即可整理图标"), systemImage: "lock.shield")
                    Spacer()
                    Button(L("查看权限")) { model.page = .permissions }
                }.padding(14).background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if !model.conflictingManagerNames.isEmpty {
                NoticeView(text: L("检测到同时运行的 %@。若图标位置反复变化，可暂停其中一款工具的整理。", model.conflictingManagerNames.joined(separator: ", ")))
            }
            if model.paused { NoticeView(text: L("整理已暂停：图标暂时显示在原菜单栏，分类和浮栏顺序仍然保留。")) }
            PlacementZone(placement: .visible)
            PlacementZone(placement: .shelf)
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                Text(L("新图标默认常驻。常用的留在外面，偶尔用的收进小屉。"))
                    .font(.system(size: 12)).foregroundStyle(secondaryText)
                Spacer()
            }
            HStack {
                Button(L("打开浮栏")) { model.toggleShelf() }.buttonStyle(.borderedProminent).controlSize(.large)
                Button(model.paused ? L("继续整理") : L("暂停整理")) { model.togglePause() }.controlSize(.large)
                Spacer()
                Text(L("系统图标在 macOS 系统设置中管理")).font(.system(size: 11)).foregroundStyle(secondaryText)
            }
        }
    }
}

private struct ZoneTileFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct ZoneDropDelegate: DropDelegate {
    let model: AppController
    let placement: ItemPlacement
    let frames: [String: CGRect]
    @Binding var isTargeted: Bool
    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let target = frames.first(where: { $0.value.contains(info.location) })?.key
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in model.dropEntry(id, into: placement, before: target) }
        }
        return true
    }
}

private struct PlacementZone: View {
    @EnvironmentObject var model: AppController
    let placement: ItemPlacement
    @State private var targeted = false
    @State private var tileFrames: [String: CGRect] = [:]
    var zoneName: String { "placement-zone-" + placement.rawValue }
    var entries: [MenuBarEntry] { model.entries.filter { $0.canMove && $0.placement == placement } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: placement == .visible ? "eye" : "tray.full.fill").foregroundStyle(.blue)
                Text(placement == .visible ? L("常驻菜单栏") : L("已收进小屉")).font(.system(size: 15, weight: .semibold))
                Text("\(entries.count)").font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12), in: Capsule()).foregroundStyle(.blue)
                Spacer()
                Text(placement == .visible ? L("点击收起") : L("点击显示")).font(.system(size: 11)).foregroundStyle(secondaryText)
            }
            if entries.isEmpty {
                HStack {
                    Image(systemName: placement == .visible ? "menubar.rectangle" : "tray")
                    Text(placement == .visible ? L("拖到这里，保留在菜单栏") : L("把不常用的图标拖到这里"))
                }.font(.system(size: 13)).foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 105), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        PlacementTile(entry: entry)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: ZoneTileFrames.self, value: [entry.id: proxy.frame(in: .named(zoneName))])
                            })
                    }
                }
            }
        }.padding(18)
            .background(placement == .shelf ? Color.blue.opacity(0.055) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(targeted ? Color.blue : Color.primary.opacity(0.18), lineWidth: targeted ? 2 : 1))
            .coordinateSpace(name: zoneName)
            .onPreferenceChange(ZoneTileFrames.self) { tileFrames = $0 }
            .onDrop(of: [.text], delegate: ZoneDropDelegate(model: model, placement: placement, frames: tileFrames, isTargeted: $targeted))
    }
}

private struct PlacementTile: View {
    @EnvironmentObject var model: AppController
    let entry: MenuBarEntry
    @State private var hovered = false
    var target: ItemPlacement { entry.placement == .visible ? .shelf : .visible }
    var actionName: String { entry.placement == .visible ? L("隐藏") : L("显示") }
    var body: some View {
        Button { model.setPlacement(entry, target) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AppIcon(entry: entry, size: 38)
                    if model.busyID == entry.id { ProgressView().controlSize(.small) }
                    else if hovered {
                        Image(systemName: target == .shelf ? "minus.circle.fill" : "plus.circle.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
                            .font(.system(size: 15)).offset(x: 5, y: 3)
                    }
                }
                Text(entry.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }.frame(maxWidth: .infinity).frame(height: 80).contentShape(RoundedRectangle(cornerRadius: 9))
                .background(hovered ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .disabled(model.busyID != nil || model.refreshing || !model.accessibility || model.spacingApplying || model.nativeActionInProgress)
            .onHover { hovered = $0 }.help("\(actionName) \(entry.name)")
            .accessibilityLabel("\(actionName) \(entry.name)")
            .onDrag { model.noteDrag("dragStarted", entryID: entry.id); return NSItemProvider(object: entry.id as NSString) }
            .contextMenu {
                if entry.placement == .shelf {
                    Button(L("向前移动")) { model.moveShelfItem(entry.id, offset: -1) }
                    Button(L("向后移动")) { model.moveShelfItem(entry.id, offset: 1) }
                    Divider()
                }
                Button(target.title) { model.setPlacement(entry, target) }
            }
    }
}

private let previewSymbols = ["link", "bubble.left.and.bubble.right.fill", "cup.and.saucer.fill", "cloud.fill", "checkmark.shield", "waveform.path.ecg"]

struct SymbolStrip: View {
    var gap: CGFloat = 20
    var size: CGFloat = 20
    var symbols: [String] = previewSymbols
    var body: some View {
        HStack(spacing: gap) {
            ForEach(symbols, id: \.self) { name in Image(systemName: name).resizable().scaledToFit().frame(width: size + 3, height: size) }
        }.foregroundStyle(.primary.opacity(0.8))
    }
}

struct AppearanceView: View {
    @EnvironmentObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(title: L("菜单栏外观"), subtitle: L("选择即保存。已有图标的生效方式见下方。"))
            HStack {
                Text(L("图标间距")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(L("设置：%@", model.currentSpacing.preset?.title ?? L("已有自定义设置"))).font(.system(size: 11)).foregroundStyle(secondaryText)
            }.padding(.bottom, 15)
            VStack(spacing: 0) {
                ForEach(Array(SpacingPreset.allCases.enumerated()), id: \.element.id) { index, preset in
                    Button { model.applySpacing(preset) } label: {
                        HStack {
                            Image(systemName: model.currentSpacing.preset == preset ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20)).foregroundStyle(model.currentSpacing.preset == preset ? .blue : Color.secondary.opacity(0.5))
                            Text(preset.title).font(.system(size: 14, weight: .medium)).padding(.leading, 8)
                            Spacer(minLength: 12)
                            SymbolStrip(gap: preset.previewGap, size: 17).frame(width: 310, alignment: .leading)
                        }.padding(.horizontal, 18).frame(height: 56)
                            .background(model.currentSpacing.preset == preset ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.spacingApplying || model.busyID != nil || model.nativeActionInProgress)
                        .accessibilityElement(children: .ignore).accessibilityLabel(preset.title)
                        .accessibilityValue(model.currentSpacing.preset == preset ? L("已选中") : L("未选中"))
                        .accessibilityAction { model.applySpacing(preset) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(model.currentSpacing.preset == preset ? [.isSelected] : [])
                    if index < 3 { Divider().padding(.horizontal, 15) }
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            Text(L("效果示意")).font(.system(size: 14, weight: .semibold)).padding(.top, 22).padding(.bottom, 12)
            HStack(spacing: 18) {
                Spacer(minLength: 0)
                SymbolStrip(gap: model.selectedSpacing.previewGap * 0.7, size: 16)
                Divider().frame(height: 21)
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Text("10:48").font(.system(size: 12, weight: .medium))
            }.padding(17).background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            Text(L("实际效果取决于系统版本及应用图标。无间隔表示最紧凑预设，不保证图标间距为零。"))
                .font(.system(size: 11)).foregroundStyle(secondaryText).padding(.top, 9)
            if let notice = model.spacingNotice { NoticeView(text: notice).padding(.top, 14) }
            Divider().padding(.vertical, 21)
            Toggle(L("选择间距时，自动重新打开下面选中的应用"), isOn: Binding(get: { model.config.reopenAppsForSpacing ?? false }, set: { model.config.reopenAppsForSpacing = $0; model.persist() }))
                .disabled(model.spacingApplying)
            Text(L("macOS 26 会缓存间距，已有图标需要重开所属应用。重开会短暂中断这些应用的连接或任务；不会强制退出，也不会注销。"))
                .font(.system(size: 11)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(model.spacingReloadTargets) { target in
                    Toggle(target.name, isOn: Binding(get: { model.isSpacingReloadSelected(target.bundleID) }, set: { model.selectSpacingReload(target.bundleID, selected: $0) }))
                        .toggleStyle(.checkbox).disabled(model.spacingApplying)
                }
            }.padding(.vertical, 12)
            if model.config.reopenAppsForSpacing != true {
                Button(L("重新打开所选应用，使间距生效")) { model.reopenSpacingApps() }
                    .disabled(model.spacingApplying || model.refreshing)
                    .padding(.bottom, 12)
            }
            Text(L("自动备份修改前的值，可一键撤销。系统图标的间距由 macOS 决定。"))
                .font(.system(size: 11)).foregroundStyle(secondaryText).padding(.bottom, 16)
            HStack {
                Button(L("恢复系统默认")) { model.applySpacing(.standard) }.disabled(model.spacingApplying)
                if model.config.pendingSpacingUndo != nil { Button(L("撤销本次修改")) { model.undoSpacing() }.disabled(model.spacingApplying) }
                Spacer()
                if model.spacingApplying { ProgressView().controlSize(.small) }
            }
        }.onAppear { model.syncSpacingSnapshot() }
    }
}

struct GeneralView: View {
    @EnvironmentObject var model: AppController
    @State private var confirmingReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: L("通用设置"), subtitle: L("保持简单，按照你的习惯使用。"))
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(L("自动收起延时")).fontWeight(.medium); Text(L("鼠标离开浮栏后开始计时，固定或操作菜单时暂停。")).font(.system(size: 11)).foregroundStyle(secondaryText) }
                        Spacer()
                        Picker(L("延时"), selection: Binding(get: { model.config.collapseDelay }, set: { model.config.collapseDelay = $0; model.persist() })) {
                            Text(L("1 秒")).tag(1.0); Text(L("1.5 秒")).tag(1.5); Text(L("3 秒")).tag(3.0); Text(L("5 秒")).tag(5.0)
                        }.labelsHidden().frame(width: 110)
                    }
                    Divider()
                    HStack {
                        Text(L("展开浮栏快捷键")).fontWeight(.medium)
                        Spacer()
                        Picker(L("快捷键"), selection: Binding(get: { model.config.shortcut }, set: { model.config.shortcut = $0; model.registerShortcut(); model.persist() })) {
                            Text("⌘ ⇧ Space").tag("commandShiftSpace"); Text("⌘ ⇧ B").tag("commandShiftB"); Text(L("关闭")).tag("none")
                        }.labelsHidden().frame(width: 160)
                    }
                    if let notice = model.shortcutNotice { Text(notice).font(.system(size: 12)).foregroundStyle(.orange) }
                    Divider()
                    Toggle(L("登录时启动"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).toggleStyle(.switch)
                }.padding(14)
            }
            HStack { Text(L("外观")); Spacer(); Text(L("跟随系统深浅色")).foregroundStyle(secondaryText) }.padding(.horizontal, 14)
            Divider()
            HStack {
                Button(L("重新查看首次启动引导")) { model.showOnboarding() }
                Spacer()
                Button(L("恢复图标整理默认配置…")) { confirmingReset = true }
                    .disabled(model.busyID != nil || model.refreshing || model.spacingApplying)
            }
            .confirmationDialog(L("恢复图标整理默认配置？"), isPresented: $confirmingReset, titleVisibility: .visible) {
                Button(L("恢复默认整理"), role: .destructive) { model.resetArrangement() }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("将清除分类和浮栏顺序，让可管理图标常驻菜单栏。间距、快捷键和登录时启动保持当前设置。"))
            }
            Text(L("关闭设置窗口后，应用仍在菜单栏中运行。右键菜单栏入口可退出。"))
                .font(.system(size: 12)).foregroundStyle(secondaryText)
        }
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: String
    let description: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.blue).frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(description).font(.system(size: 12)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Label(granted ? L("已授权") : L("未授权"), systemImage: granted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11)).foregroundStyle(granted ? .green : .secondary)
                Button(granted ? L("查看设置") : L("去设置"), action: action)
            }
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

struct PermissionsView: View {
    @EnvironmentObject var model: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: L("权限与帮助"), subtitle: L("你来决定允许哪些访问。授权状态从系统实时读取。"))
            PermissionRow(symbol: "accessibility", title: L("辅助功能"), description: L("移动图标，并从浮栏调用原菜单栏操作。"), granted: model.accessibility) { model.openPermission(false) }
            PermissionRow(symbol: "rectangle.dashed.badge.record", title: L("屏幕录制"), description: L("按需截取菜单栏图标。未授权时使用应用图标作为替代。"), granted: model.screenCapture) {
                if model.screenCapture { model.openPermission(true) } else { model.requestScreenPermission(); model.openPermission(true) }
            }
            HStack {
                Label(L("图标图像仅在本机内存中处理，不保存或上传。"), systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(secondaryText)
                Spacer()
                Button(L("重新检查")) { model.checkPermissions(); Task { await model.refresh() } }
            }.padding(.vertical, 7)
            Divider().padding(.vertical, 8)
            Text(L("找不到图标？")).font(.system(size: 17, weight: .semibold))
            Text(L("点击暂停整理以展开图标。也可从应用启动器重新打开本工具。系统空间不足或刘海遮挡时，图标可能仍无法同时显示。"))
                .foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
            Button(L("暂停整理，展开全部")) { if !model.paused { model.togglePause() } }
            Text(L("当前版本：原生 Apple Silicon 开发预览。系统项目自动移动、刘海后图标临时移出及完整跨屏兼容仍需实机验证。"))
                .font(.system(size: 11)).foregroundStyle(secondaryText).padding(.top, 10)
        }.onAppear { model.checkPermissions() }
    }
}

private final class NativeTrayButton: NSButton {
    var onLeft: ((NSEvent.ModifierFlags) -> Void)?
    var onRight: ((NSEvent.ModifierFlags) -> Void)?
    @objc func invoke() { onLeft?(NSApp.currentEvent?.modifierFlags ?? []) }
    private var trackingControlClick = false
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { trackingControlClick = true }
        else { super.mouseDown(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if trackingControlClick { trackingControlClick = false; onRight?(event.modifierFlags.subtracting(.control)) }
        else { super.mouseUp(with: event) }
    }
    override func rightMouseUp(with event: NSEvent) { onRight?(event.modifierFlags) }
}

private struct TrayClickSurface: NSViewRepresentable {
    let name: String
    let left: (NSEvent.ModifierFlags) -> Void
    let right: (NSEvent.ModifierFlags) -> Void
    func makeNSView(context: Context) -> NativeTrayButton {
        let button = NativeTrayButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.target = button; button.action = #selector(NativeTrayButton.invoke)
        return button
    }
    func updateNSView(_ button: NativeTrayButton, context: Context) {
        button.onLeft = left; button.onRight = right
        button.toolTip = L("%@ · 右键打开原右键菜单", name)
        button.setAccessibilityLabel(L("打开 %@ 菜单", name))
    }
}

struct ShelfView: View {
    @EnvironmentObject var model: AppController
    var hidden: [MenuBarEntry] { model.entries.filter { $0.canMove && $0.placement == .shelf } }
    var layout: ShelfLayout { model.shelfLayout }

    private var icons: some View {
        HStack(spacing: ShelfLayout.itemSpacing) {
            ForEach(hidden) { entry in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(entry.trayImage != nil && entry.trayNeedsDarkBackdrop ? Color(red: 0.12, green: 0.17, blue: 0.23) : Color.white)
                    AppIcon(entry: entry, size: 29, tray: true)
                    TrayClickSurface(name: entry.name, left: { model.activate(entry, modifiers: $0) }, right: { model.activate(entry, right: true, modifiers: $0) })
                }.frame(width: ShelfLayout.tileWidth, height: ShelfLayout.tileHeight)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.22), lineWidth: 1))
            }
        }.padding(ShelfLayout.contentPadding)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        Group {
            if !model.accessibility {
                VStack(spacing: 10) {
                    Text(L("需要辅助功能权限才能操作图标")).font(.system(size: 12, weight: .medium))
                    Button(L("打开权限与帮助")) { model.closeShelf(); model.showSettings(.permissions) }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hidden.isEmpty {
                VStack(spacing: 10) {
                    Text(L("小屉里还没有图标")).font(.system(size: 13, weight: .medium))
                    Button(L("打开图标整理")) { model.closeShelf(); model.showSettings(.items) }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: ShelfLayout.sectionSpacing) {
                    if layout.needsHorizontalScrolling {
                        ScrollView(.horizontal, showsIndicators: true) { icons }
                            .frame(width: layout.viewportWidth, height: ShelfLayout.tileHeight + 2 * ShelfLayout.contentPadding)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.right.circle.fill").symbolRenderingMode(.palette)
                                    .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
                                    .help(L("横向滚动查看更多图标")).allowsHitTesting(false)
                            }
                    } else {
                        icons.frame(width: layout.viewportWidth, alignment: .leading)
                    }
                    Divider().frame(width: ShelfLayout.dividerWidth, height: 30)
                    Button { model.pinned.toggle() } label: {
                        Image(systemName: model.pinned ? "pin.fill" : "pin").font(.system(size: 16, weight: .medium)).frame(width: ShelfLayout.controlWidth, height: ShelfLayout.tileHeight)
                    }.buttonStyle(.plain).foregroundStyle(model.pinned ? .blue : .primary)
                        .help(model.pinned ? L("取消固定") : L("临时固定浮栏"))
                        .accessibilityLabel(model.pinned ? L("取消固定浮栏") : L("固定浮栏"))
                        .accessibilityValue(model.pinned ? L("已固定") : L("未固定"))
                    Button { model.closeShelf(); model.showSettings(.items) } label: {
                        Image(systemName: "gearshape").font(.system(size: 18, weight: .medium)).frame(width: ShelfLayout.controlWidth, height: ShelfLayout.tileHeight)
                    }.buttonStyle(.plain).help(L("图标整理")).accessibilityLabel(L("打开图标整理"))
                }.padding(.horizontal, ShelfLayout.horizontalPadding).padding(.vertical, ShelfLayout.verticalPadding)
            }
        }.frame(width: layout.width, height: layout.height)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.22), lineWidth: 1))
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppController
    let labels = [L("了解用途"), L("权限说明"), L("收起并找回")]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<3) { index in
                    if index > 0 { Rectangle().fill(index <= model.onboardingStep ? .blue : Color.secondary.opacity(0.2)).frame(height: 1).padding(.bottom, 24) }
                    VStack(spacing: 9) {
                        ZStack {
                            Circle().fill(index <= model.onboardingStep ? .blue : Color.secondary.opacity(0.12)).frame(width: 29, height: 29)
                            if index < model.onboardingStep { Image(systemName: "checkmark").foregroundStyle(.white) }
                            else { Text("\(index + 1)").foregroundStyle(index == model.onboardingStep ? .white : .secondary) }
                        }
                        Text(labels[index]).font(.system(size: 12, weight: index == model.onboardingStep ? .medium : .regular))
                            .foregroundStyle(index == model.onboardingStep ? .blue : .secondary)
                    }.frame(width: 100)
                }
            }.frame(maxWidth: 590).padding(.top, 35).padding(.bottom, 35)
            Group {
                switch model.onboardingStep {
                case 0: introduction
                case 1: permissions
                default: tryIt
                }
            }.frame(maxWidth: 590)
            Spacer(minLength: 15)
            if let message = model.message { NoticeView(text: message) { model.message = nil }.frame(maxWidth: 590).padding(.bottom, 12) }
            HStack {
                if model.onboardingStep > 0 { Button(L("上一步")) { model.onboardingStep -= 1 }.controlSize(.large) }
                Spacer()
                Button(model.onboardingStep == 2 ? L("稍后整理") : L("稍后设置")) { model.finishOnboarding() }.buttonStyle(.link)
                Button(primaryTitle, action: primaryAction).buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.busyID != nil || (model.onboardingStep == 2 && model.onboardingSelected == nil))
            }.frame(maxWidth: 590).padding(.bottom, 35)
        }.padding(.horizontal, 30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
    }
    var primaryTitle: String {
        if model.onboardingStep == 0 { return L("继续") }
        if model.onboardingStep == 1 { return L("检查权限并继续") }
        if model.onboardingTrialAccessed { return L("完成") }
        return model.onboardingTrial == nil ? L("收起并试用") : L("打开小屉，找回图标")
    }
    func primaryAction() {
        if model.onboardingStep == 0 { model.onboardingStep = 1 }
        else if model.onboardingStep == 1 {
            model.checkPermissions()
            guard model.accessibility else { model.message = L("请先授权辅助功能，或选择稍后设置。屏幕录制可以稍后开启。"); return }
            model.message = nil; model.onboardingStep = 2
            Task { await model.refresh(); model.onboardingSelected = model.entries.first(where: { $0.canMove })?.id }
        } else if model.onboardingTrialAccessed { model.finishOnboarding() }
        else if model.onboardingTrial != nil { model.toggleShelf() }
        else if let entry = model.entries.first(where: { $0.id == model.onboardingSelected }) { model.beginOnboardingTrial(entry) }
    }
    var introduction: some View {
        VStack(spacing: 18) {
            Text(L("让菜单栏清爽一点")).font(.system(size: 30, weight: .bold))
            Text(L("常用的留在外面，偶尔用的收进浮栏。")).foregroundStyle(secondaryText)
            VStack(alignment: .leading, spacing: 16) {
                Text(L("整理前")).font(.system(size: 11)).foregroundStyle(secondaryText)
                SymbolStrip(gap: 28, size: 22).frame(maxWidth: .infinity).padding(17).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                Image(systemName: "arrow.down").foregroundStyle(.blue).frame(maxWidth: .infinity)
                Text(L("整理后")).font(.system(size: 11)).foregroundStyle(secondaryText)
                HStack {
                    Image(nsImage: model.service.entranceImage).renderingMode(.template).foregroundStyle(.blue)
                    SymbolStrip(gap: 16, size: 18, symbols: Array(previewSymbols.prefix(2)))
                    Spacer(); Image(systemName: "wifi"); Image(systemName: "battery.100percent")
                }.padding(16).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                SymbolStrip(gap: 16, size: 19, symbols: Array(previewSymbols.dropFirst(2))).padding(17).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity)
            }.padding(22).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13)).padding(.top, 8)
            Text(L("以上为效果示意。开始前，不会自动隐藏任何图标。")).font(.system(size: 12)).foregroundStyle(secondaryText)
        }
    }
    var permissions: some View {
        VStack(spacing: 18) {
            Text(L("允许访问菜单栏图标")).font(.system(size: 28, weight: .bold))
            Text(L("用于显示并操作你收起的图标。")).foregroundStyle(secondaryText).padding(.bottom, 7)
            PermissionRow(symbol: "accessibility", title: L("辅助功能"), description: L("移动和操作菜单栏图标"), granted: model.accessibility) { model.openPermission(false) }
            PermissionRow(symbol: "rectangle.dashed.badge.record", title: L("屏幕录制 · 可选"), description: L("获取原图标图像；未授权时使用应用图标"), granted: model.screenCapture) { model.requestScreenPermission(); model.openPermission(true) }
            Label(L("仅在本机内存中处理图标图像，不保存或上传。"), systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(secondaryText).padding(.top, 10)
        }.onAppear { model.checkPermissions() }
    }
    var tryIt: some View {
        VStack(spacing: 19) {
            Text(L("收起，再找回")).font(.system(size: 30, weight: .bold))
            Text(L("先选一个不常用的图标试试看。")).foregroundStyle(secondaryText)
            if model.entries.filter({ $0.canMove }).isEmpty {
                NoticeView(text: L("暂未发现可移动的项目。请先打开带菜单栏图标的应用，或稍后到图标整理页刷新。"))
            } else {
                Picker(L("选择一个图标"), selection: $model.onboardingSelected) {
                    Text(L("请选择")).tag(String?.none)
                    ForEach(model.entries.filter { $0.canMove }) { entry in Text(entry.name).tag(Optional(entry.id)) }
                }.pickerStyle(.menu).disabled(model.onboardingTrial != nil).padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 16) {
                Image(nsImage: model.service.entranceImage).renderingMode(.template).resizable().scaledToFit().frame(width: 58, height: 58).foregroundStyle(.blue)
                Text(model.onboardingTrialAccessed ? L("已通过浮栏访问原图标，可以开始使用小屉了。") : (model.onboardingTrial == nil ? L("收起后，点击菜单栏的抽屉图标找回。") : L("已收进小屉。打开浮栏后，点击刚才的图标试用原菜单或操作。"))).font(.system(size: 15, weight: .medium))
                Text(L("随时可以在图标整理中恢复常驻。")).foregroundStyle(secondaryText)
            }.frame(maxWidth: .infinity).padding(.vertical, 35).background(Color.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        }
    }
}
