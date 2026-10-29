# Testing and limitations / 测试与限制

## Status / 状态

This is a developer preview, not a finished compatibility-certified release. Read the individual release notes for the exact tested binary. Source changes after those checks are not automatically covered.

当前是开发预览；请以对应 Release 的二进制验收说明为准，不能把旧版本结果沿用到新源码。

## Automated checks / 自动检查

- CoreChecks covers stable item identity, transitional geometry, entrance ordering, first visible insertion, single-row shelf size/overflow, spacing snapshots/undo serialization, configuration migration, collapse safeguards, shelf reordering, explicit relaunch consent, and bilingual resource loading/format arguments.
- `scripts/check-localizations.py` audits matching English/Chinese catalogs, placeholders, untranslated Swift literals, localized app names, and permission metadata.
- Release compilation, bundled resources, arm64 architecture, and code signature integrity are checked separately. An ad-hoc signature is not a notarization or trust certification.
- CI builds do not grant Accessibility or interact with another app's menu bar. They cannot prove flicker, original context menus, timing, or permission recovery.

核心检查覆盖身份、过渡坐标、入口顺序、显示插入位置、单行布局、间距与配置迁移、收起保护、排序、重开选择和中英文资源。语言审计检查资源对应、占位符、界面文本与元数据。构建、架构、资源和临时签名另行检查；CI 不代替真实桌面验收。

## Native test matrix / 实机检查清单

Test on an unlocked desktop, save original configuration, use a disposable helper app for relaunch/shortcut conflict tests, then restore settings. Do not force-quit a user's applications.

| Flow / 流程 | Required cases / 检查项 |
| --- | --- |
| Welcome / 引导 | Skip, deny/allow permissions, one-icon hide and recovery, guide reopening / 跳过、拒绝/授权、收起找回、重新引导 |
| Classification / 分类 | Show/hide, all shown/all hidden, repeated toggles, new app, source rebuild/relaunch, position persistence / 单项、全显全藏、反复切换、新来源与重建、保存 |
| Motion / 移动 | Target only, no hidden peer reveal, first visible slot, leading entrance, retry and failure behavior, pointer recovery / 仅目标、同伴不露出、左侧顺序、重试失败与鼠标恢复 |
| Drawer / 浮栏 | Full icon bounds, one row, narrow screen overflow, pin, delay, Esc/outside close / 完整图标、单行、超宽、固定、延时与关闭 |
| Original actions / 原操作 | Left, right, Control-click, modifiers, submenu and actual safe command, return target only / 左右键、修饰键、子菜单、真实命令与收回 |
| Sorting / 排序 | Same zone, cross zone, background append, keyboard/menu alternative, cold start / 同区、跨区、追加、菜单替代与冷启动 |
| Spacing / 间距 | Four presets, same preset no-op, unset/custom values, undo, external change, selected helper reopening / 四档、同档无操作、自定义、撤销、外部修改与助手重开 |
| Shortcut / 快捷键 | Other app foreground, both choices, disabled passthrough, conflict, no stuck modifiers / 他程序前台、两组键、关闭透传、冲突与修饰键释放 |
| Recovery / 恢复 | Pause/resume, normal quit, reset confirm/cancel, permissions revoked/restored / 暂停、退出、重置确认取消、权限撤回恢复 |
| Language / 语言 | English, Chinese, app name, all settings, onboarding, menu and error labels, permission text / 双语名称、页面、引导、菜单错误与权限说明 |
| Physical / 实体环境 | Dark/light, Retina/non-Retina, notch, multiple displays, Spaces/fullscreen, sleep/wake, login / 深浅色、分辨率、刘海、多屏、空间、唤醒、登录 |

## Current native regression / 当前实机回归

### 0.1.13 shipped regression / 发布版回归

Executable SHA-256: `cdbd8310799268fb45059df358f032536688b0fdfafd20b423b227e2507ccd83`. Tested on M1 / macOS 27.2 (26B123), arm64, one 1440×900 non-notched Retina display, with Accessibility and single-file ordering access. Screen Recording was not granted to the application. The same executable is packaged in both release archives.

- All 22 CoreChecks groups passed in English and Simplified Chinese; 181 bilingual strings passed the audit.
- The dedicated native smoke flow passed: newly launched source discovery, three verified hide/show rounds, real drawer opening, original menu opening and automatic target rehide, pause/assertion release, normal probe termination and byte-for-byte configuration restoration.
- 22 additional manual placement transactions all succeeded on the first attempt. Cases included all-six hidden, six full single-row drawer buttons, pin/Esc, wide SSRUN slots, individual restore, and the final hidden item becoming visible with system-slot reservation. Confirming geometry checked a leading entrance, adjacent target within 3 points, target still hidden during reservation, and zero cursor displacement. No movement was replayed.
- Twelve of those moves were captured in a local 45-second, menu-bar-only recording: 2,513 delivered frames, no audio. Entrance-template inspection found no missing or duplicate entrance glyph; minimum match score 0.960. This is an observed sample, not proof against every possible transient. Hide completion: 1,011–1,033 ms (median 1,021); show: 708–789 ms (median 734), while recording. Raw video and derived imagery were deleted after analysis.
- The final binary opened Caffeine’s real context menu through one verified native Control-click, observed nine menu items, then restored the hidden target after closing. A disposable text field received exactly `456` from three single-key inputs. Earlier physical-user checks independently confirmed normal typing and Command-Shift-Space opening through Carbon; that keyboard path is unchanged in this binary.
- Normal quit, exact original-configuration restoration and cold start passed: the controller was idle, the entrance led the app group, and ChatGPT’s saved hidden category was actually restored.

Earlier candidates were rejected when manual review found one-frame entrance gaps, including low scores that the old automatic threshold incorrectly matched to other artwork. The final build forces proxy drawing, checks actual window visibility and retains the original artwork through the first compositing interval. Older binary results are not counted as this release’s recorded transactions.

On the validated macOS 27 host, an own-window sharing session can restore a 48-point system privacy capsule when the last restriction ends. Live/inferred system widths take precedence; an unsampled active own-window sharing session uses this measured footprint. Actual adjacent geometry must still match or the transaction rolls back. Different privacy-module layouts remain unverified; this is not a universal sizing guarantee. The OS-owned module animation is outside DrawerBar’s control.

发布二进制哈希见上；M1 / macOS 27.2、单屏无刘海，辅助功能与单个排序文件已授权，应用本身未授权录屏。22 组双语核心检查、181 条语言审计和专用助手完整自检通过。同一程序另完成 22 次一次成功的分类切换，覆盖六项全藏、单行完整显示、固定与 Esc、宽图标、逐项恢复及最后一项显示。12 次切换录制了 2,513 个顶部菜单栏帧，入口模板最低匹配 0.960，未检测到缺失或重复；不代表所有未来瞬态均已排除。录像与拆帧图分析后删除，不上传。原右键菜单、三次单键输入、正常退出、原配置逐字节恢复和冷启动实际恢复隐藏分类通过。此前失败候选不计入本版验收结果。刘海、多屏、其他系统、系统动态模块的所有变体、真实重启登录和能耗仍未全面验收；macOS 27 浮栏仍按应用使用应用图标，免重开的即时间距未完成。

### Earlier macOS 27.2 probe regression / 较早的 macOS 27.2 助手回归

The installed local executable SHA-256 is `f5ecd106c0355fe8927452b25edf1c637bc984ff93f82e0a49113886667a23b0`. It is an unpublished arm64 build based on `30229a0`, tested on macOS 27.2 (26B123) with Accessibility and single-file ordering access, without Screen Recording. Its dedicated probe passed three hide/show cycles, real drawer opening, temporary reveal of its original two-item menu, observed AX menu opening/closing with automatic rehide, and pause/assertion release. Original configuration was restored byte for byte and the probe terminated normally. The parent workspace contains `outputs/order-rules/native-menu-smoke-confirmed-action.json` and `native-menu-action-evidence.json`.

The native action path resolves source and live hosted AX elements. `AXPress` can return `cannotComplete` while menu tracking continues; that ambiguous result is accepted only when actual menu notifications or a visible native popup confirm delivery, without replaying the action. Closed cached AX trees are not used to infer that a menu is open.

本地已安装程序哈希见上，基于 `30229a0`，未发布新 Release。macOS 27.2（26B123）、arm64，仅授权辅助功能及单个排序文件，屏幕录制关闭。三轮隐藏/显示、真实浮栏打开、临时显示测试图标并打开原两项菜单、菜单关闭后自动收回、暂停并释放限制均通过；原配置逐字节恢复，助手正常退出。原菜单调用会同时查找来源及宿主的实际辅助功能元素；遇到 `AXPress` 无法及时回复时，必须由真实菜单通知或在屏浮窗确认已经送达，不重复点击。

On that same executable, the ordering regression passed three rounds on two displays: a 1512×982 notched primary and a 1440×2560 secondary. Dedicated icons occupied 16-point and 44-point native slots. Each hide checked a leading entrance, rightward movement by the removed slot width for every left peer, and unchanged right peers on both displays. Each show checked that the target was still hidden during space reservation, that the visual entrance stayed at its reserved position, and that the revealed target was immediately right of it on both displays. Only test/entrance weights were restored afterward, with unrelated application weights preserved; original classification was restored byte for byte. See `outputs/order-rules/native-order-smoke-current.json` in the parent workspace. The 21 CoreChecks groups, 181-string localization audit, release compilation, arm64 architecture and strict ad-hoc signature verification passed.

同一程序在 1512×982 刘海主屏及 1440×2560 副屏完成三轮排序检查，专用窄/宽图标实际占位分别为 16pt / 44pt。逐屏核对入口最左、隐藏后左侧同伴按目标宽度右移、右侧同伴不动；显示时先在目标仍隐藏的状态预留空位，入口保持在预留位置，目标紧邻入口右侧。结束后仅恢复测试与入口排序值，其他应用数值保持不变，分类逐字节恢复。21 组核心检查、181 条双语资源审计、Release 构建、arm64 架构与严格临时签名校验通过。

This remains limited to dedicated probes on the current Mac. It does not establish support for every third-party menu, custom popover, display topology change, login, or frame-by-frame animation. Items are grouped by source application. A notched display must have enough usable space before an item is revealed; otherwise the hidden classification is retained. Some Apple dynamic modules can disappear while visibility restrictions are active, and the right-hand system area temporarily releases those restrictions.

覆盖范围限于当前 Mac 的专用测试助手，不代表全部第三方菜单、自定义浮窗、屏幕拓扑切换、登录或逐帧动画已验收。同一应用的图标一起切换；刘海屏显示前需要留有足够空间，空间不足时保留隐藏分类。部分 Apple 动态模块在限制期间可能暂时消失；操作菜单栏右侧系统区域时会暂时解除限制。

### Earlier macOS 27.2 visibility build / 较早的 macOS 27.2 隐藏构建

The local candidate executable SHA-256 is `8714576a507236b2709c29c2970ab7c39a88da1b770875bb5ebe865664ac1b67`. This is an untagged local build based on commit `30229a0`, not a new published release. Tests ran on macOS 27.2 (26B123), arm64, from `/Applications/DrawerBar.app`, with Accessibility granted and Screen Recording denied.

The dedicated `local.drawerbar.probe` helper was discovered through Accessibility. Three hide/show cycles passed with two confirming MenuBarAgent drawn-owner observations per movement. The real drawer panel opened with the hidden helper. A drawer action temporarily revealed the helper, opened its original two-item menu, received actual AX menu-open/menu-close notifications, and automatically hid it again. Releasing the assertion restored the helper. The helper exited normally, and its original configuration snapshot was restored byte for byte. The report is `outputs/macos27/native-smoke.json` in the parent workspace. App state was idle afterward, with no temporary item and no active restriction.

The native app uses source identities and a temporary visibility assertion; per-item WindowServer windows are not required. Closed AX menu trees and missing popup-window records are not treated as menu tracking: AX notifications are observed instead. The 20 CoreChecks groups, 172-string localization audit, release compilation, and strict ad-hoc signature verification passed.

This covers one helper app on this macOS build, not arbitrary third-party menus or frame-by-frame animation. The adapter groups items by app, uses app artwork in the drawer, and leaves physical ordering to Command-drag. Some Apple dynamic modules may disappear while the restriction is active. The right-hand system area temporarily releases restrictions for system panels. Display topology changes, login, custom popovers, and other OS builds remain unverified.

本地候选程序哈希见上，基于 `30229a0`，没有发布新 Release。macOS 27.2（26B123）、arm64、安装于 `/Applications`，仅授权辅助功能，屏幕录制关闭。专用测试图标完成三轮收起/显示，每次移动均核对 MenuBarAgent 实际绘制来源的两次连续采样；浮栏、临时显示原图标、原两项菜单打开/关闭通知、自动收回和释放白名单恢复显示均通过。测试助手正常退出，原配置逐字节恢复，结束后控制器空闲、无临时图标、无活动限制。20 组核心检查、172 条语言检查、Release 构建与严格临时签名校验通过。

覆盖范围限于这台 Mac 和测试助手，不代表所有第三方原菜单、自定义浮窗、逐帧动画、登录及多屏切换都已验收。同一应用的图标一起隐藏，浮栏使用应用图标，物理顺序交给系统 ⌘ 拖动；系统右侧区域会暂时解除隐藏，部分 Apple 动态模块在限制期间可能暂时消失。

### 0.1.12 native motion / 原生移动验收

The shipped arm64 executable SHA-256 is `c1dc0b4da2f0596529b0eb563bf2614253783809387dc1b25b6091b7f224ea26`. The following checks used that same installed binary on an M1, macOS 26.6.2, one Retina display without a notch. No source-code changes were made after these device tests.

发布程序哈希见上。本轮使用同一个已安装二进制，设备为 M1、macOS 26.6.2、单屏 Retina、无刘海；实测后没有改动程序源码。

- 34 native classification moves covered six shown, six hidden, a lone wide SSRUN meter, a lone ChatGPT icon, and repeated narrow/wide toggles. All 34 succeeded on the first attempt with correct saved/UI classification, a leading entrance, first shown slot, and no protected-system-order violation. Hide times were 228–488 ms; show times were 466–739 ms; overall median was 473 ms. These include pickup, insertion-gap preparation, and two position-confirmation samples; they are not perceived animation-duration measurements.
- 162 geometry samples detected no full hidden-region expansion or hidden-peer exposure. All 34 logged zero cursor displacement. Geometry alone is not visual evidence.
- A user-authorized recording captured only the top menu bar, 2880×52 pixels, no audio. It yielded 4,288 delivered frames over 120 seconds (variable capture cadence, not guaranteed 60 fps). All 17 show onsets and 17 hide transitions were reviewed in consecutive-frame contact sheets. No insertion artwork collision, target flash-back, or hidden-peer flash was observed in those inspected transitions. Four fixed-coordinate template interruptions were checked manually: the wide icon remained visible while native layout shifted it a few pixels. This is limited observed coverage, not proof against every transient or future configuration.
- The same binary opened ChatGPT's original six-item right-click menu using a target-only temporary reveal on the first attempt. The user pressed Esc because Computer Use could not control that source app. Automatic recovery then returned only the target to the drawer in 199 ms, first attempt; the controller became idle. Global shortcut open and Esc close also passed; a shortcut event from System Settings was recorded as opening the drawer.
- All 19 core groups passed in English and Simplified Chinese; the 168-string audit, arm64 executable, and strict ad-hoc signature verification passed. Core checks include route compatibility, late confirmation without replay, and actual drawer artwork versus padded hit bounds. Normal quit/relaunch passed. The exact original configuration and the original six-icon native order were restored and compared after cold start.
- Rejected experimental binaries and their timings are excluded from these results. Recordings and derived images were deleted after analysis. No personal diagnostics, configuration, captures, or test helpers are bundled publicly.

34 次切换覆盖六项全显 / 全藏、单个宽图标、单个 ChatGPT 及反复切换，均一次成功；分类、入口靠左、首个插入位置和系统顺序通过。隐藏 228–488ms，显示 466–739ms，中位 473ms，属于含位置校验的事务总耗时。162 个几何样本未见整区展开或同伴露出，鼠标位移记录均为零。

仅顶部菜单栏的授权录像共 4,288 帧，已查看 17 次显示和 17 次隐藏过渡的连续帧，未复现图形重叠、目标闪回或同伴闪出；4 处固定坐标模板中断经人工核对属于宽图标随布局移动。录像并非保证每秒 60 帧，结果仅限检查范围。原右键菜单打开后由用户按 Esc，目标自动收回通过；快捷键和 Esc 收起通过。19 组中英文核心检查、168 条语言审计、架构和签名检查通过；冷启动后原配置与六个图标的原生顺序均已恢复核对。私人录屏和拆帧图分析后删除，不公开上传。

### Historical scan-only candidate / 历史仅减少扫描的候选

The following measurements describe a rejected earlier candidate, not 0.1.12. / 以下为先前候选记录，不代表 0.1.12。



The retained local executable SHA-256 is `86284f2f07967a5621442518f77354c0a2075ce06c1cedf15621e04f08272563`. On the same M1 / macOS 26.6.2 / single display, 16 native classification moves covered all six shown, all six hidden, and repeated narrow/wide-icon toggles. Every move passed saved/UI classification, a leading entrance, the protected system boundary, no full-region expansion or hidden-peer exposure in geometry samples, and zero cursor displacement. Fourteen moves used one attempt; two needed retries. Observed native move times were 217–1343 ms, median 432 ms. These are measurements, not an improvement claim or an animation pass.

保留的本地二进制哈希见上。同一 M1 / macOS 26.6.2 / 单屏完成 16 次分类切换，覆盖六项全显、全藏与宽窄图标反复切换。分类、入口靠左、系统边界、几何样本中隐藏同伴不露出与整区不展开、鼠标位移为零均通过；14 次一次成功，2 次发生重试。原生移动耗时 217–1343ms，中位 432ms。这是本次测量，不是速度提升或动画通过的声明。

For 24 seconds after the final toggle, diagnostics recorded no automatic full layout synchronization. All 16 core groups passed in English and Simplified Chinese; the 168-string audit, arm64 release build, and ad-hoc signature verification passed. The original configuration was restored after testing. No raw diagnostics or personal recordings are included in the repository.

最后一次切换后观察 24 秒，未记录到自动全量布局同步。16 组核心检查在中英文模式下通过，168 条语言审计、arm64 Release 构建及临时签名检查通过。测试后恢复原配置；私人诊断与录屏不进入仓库。

Four separate motion candidates were rejected: destination-aligned pickup still visibly overlapped; batching down/up and actual-coordinate pickup failed native placement; reserving a single slot still produced a slow retry. All experimental event, reservation, and transition changes were removed. Temporary top-menu-only recordings and derived frames were deleted after analysis. The retained build uses the prior native movement mechanism. **The requested overlap-free, consistently fast movement has not passed acceptance, and no new release is published for it.**

四个动画候选均被否决：目标附近拾取仍出现可见重叠；成对投递和真实坐标拾取未完成原生移动；预留单个空位仍有慢重试。实验事件、空位和过渡逻辑全部撤回，顶部菜单栏临时录屏与拆帧图分析后删除。保留构建继续使用原移动机制。**无重叠且持续快速的移动尚未通过验收，因此不为此发布新版。**

### 0.1.11 system boundary / 系统图标边界

The targeted ordering regression passed on the same M1 / macOS 26.6.2 / single non-notched display. Eighteen candidate moves covered SSRUN as the only visible app, all six hidden, all six shown, and repeated hide/show. Four additional moves on the ordering candidate, before the subsequent drawer restyling, covered SSRUN hide/show and ChatGPT show/hide. All 22 moves succeeded on the first attempt. Each recorded result checked the entrance, actual visible application positions before the protected group, and the unchanged relative order of the system anchor windows. Geometry samples detected no hidden-peer exposure or full-region expansion. Those four ordering-candidate moves took 236–351 ms; they are not new timing measurements of the later styled binary.

同一 M1 / macOS 26.6.2 / 单屏无刘海环境中，候选版 18 次操作覆盖仅 SSRUN 常驻、六项全藏全显及反复切换；后续浮栏改版前的排序候选二进制又完成 SSRUN 隐藏 / 显示、ChatGPT 显示 / 隐藏四次操作。22 次均一次成功，并检查入口、应用位于系统组左侧、系统参照窗口相对顺序不变。几何样本未检测到隐藏同伴露出或整区展开；这四次排序候选版耗时 236–351 ms，不是后来样式改版二进制的新耗时测量。

The OS capture/privacy indicator is explicitly excluded from discovery and ordering; it is not a movable app or system insertion anchor. The user's original categories, drawer order, and other configuration were restored after testing. No private native diagnostics are bundled in the public repository or installer. This is a position/order check, not a new frame-by-frame animation certification; the earlier animation-overlap and spacing limitations remain open.

系统录屏隐私指示器明确不参与发现及排序。测试后恢复用户原分类、浮栏顺序及其他配置；私人诊断不进入公开仓库或安装包。这是位置与顺序验收，不是新的逐帧动画证明；既有动画重叠及间距限制仍然存在。

### 0.1.11 styled binary / 浮栏样式改版二进制

The shipped executable SHA-256 is `b802caf0e6df438d894f4e87e87d24e68d485c65efd2450135e461977d37354f`. On the same Mac, native previews covered an empty drawer, one Flux icon, a wide SSRUN meter, and all six hidden icons with WeChat unread text. Background color sampling, original point sizes, no icon cards, a single row, pinning, automatic/Esc drawer closing, and the empty row opening Organize Icons were inspected. English/Chinese empty-row text was measured to fit; the 15 core groups passed in both languages and the 168-string audit passed.

Flux's original context menu opened. Computer Use could not control the menu-only application to close it, so the user closed that native menu. Afterward the app was verified idle, with the original saved configuration restored, five apps visible and only Flux hidden, a leading entrance, and no system-boundary violation. This is targeted native coverage, not a full native-menu roundtrip automation or a new 22-move test of the styled binary. Other displays/wallpapers and denied-permission appearance were not natively exercised in this pass.

发布二进制哈希见上。同一 Mac 已实测空浮栏、单个 Flux、SSRUN 宽网速图标、六个隐藏图标及 WeChat 未读数；核对菜单栏配色、原始尺寸、无图标卡片、单行、固定、自动 / Esc 收起及空状态一键打开整理页。中英文提示测量均能容纳；15 组双语核心检查与 168 条语言审计通过。

Flux 原右键菜单已打开；Computer Use 无法控制其纯菜单栏应用进行关闭，由用户关闭。随后核对控制器空闲、原配置一致、五项常驻且仅 Flux 隐藏、入口靠左、未越过系统边界。这是定向实测，不是完整原菜单自动化回环，也不是样式版重新完成了此前 22 次排序测试；其他屏幕 / 壁纸、拒绝权限外观未在此轮实机验收。

In 0.1.10 development, two experimental pickup-coordinate approaches failed the actual placement check. They were withdrawn; ordinary icon movement uses the prior 0.1.9 base path. Further motion/flicker investigation is still open. Do not read the bilingual release as completion of the full native regression.

0.1.10 开发中，两种实验拾取坐标方案均未通过真实位置校验，已撤回；常规移动恢复为 0.1.9 的基础路径。轨迹与闪动仍需进一步调查。双语开源不代表完整实机验收已经完成。

## Known limits / 已知限制

The current 0.1.13 regression uses one M1, macOS 27.2, non-notched display. Older records above describe different binaries and display setups; they do not certify this candidate on multiple displays or notched MacBooks. Real login-after-reboot and energy measurements are not certified. A geometry sample is not a captured frame: it cannot prove that no transient pixel or ghost ever appeared. Never label an unrecorded motion test “flicker-free.”

当前 0.1.13 回归环境为 M1、macOS 27.2、单屏无刘海。上文历史结果属于不同二进制及屏幕环境，不能沿用为当前候选的多屏、刘海验收；重启登录与能耗仍未验收。几何样本不能证明每帧都没有闪动；未录制的移动不能标注“绝不闪动”。

Spacing adoption without source app reopening remains unresolved. Context menus depend on source app behavior. Preview builds are not notarized, and rebuilding may invalidate existing macOS permission records.

免重开的间距即时生效仍未完成，原菜单取决于来源应用，预览版未公证，重新构建可能使旧授权失配。

## 0.1.10 localization preview evidence / 双语预览验收记录

- English and Simplified Chinese app windows were opened on the same Mac. Localized names, settings navigation, permission messages, and the English welcome guide were inspected. Core resource loading and format arguments passed in both language modes; 168 text keys passed the catalog audit.
- 28 logged real icon moves on the base path all succeeded on the first attempt. The set included all six icons hidden and shown, plus repeated toggles. Transaction geometry samples found no full-region expansion or hidden-peer exposure. These samples do not prove visual smoothness.
- With explicit user consent, two local 25-second recordings captured only the top menu bar (2880×52, no audio). Baseline playback reproduced brief insertion overlap. A slot-reservation experiment moved the target successfully but added extra peer motion and latency, so it was rejected and is absent from the preview source. Videos and derived images were deleted after analysis; no personal recordings or raw diagnostics were published.
- This release does **not** claim completion of the full native test matrix, resolution of animation overlap, or equivalence to iBar. Notch, multi-display, other OS versions, original-menu edge cases, and the broader regression remain open.

同一台 Mac 已打开中英文界面，核对名称、设置导航、权限提示与英文引导；两种语言核心检查及 168 条资源审计通过。基础路径的 28 条真实移动记录均一次成功，覆盖六个项目全藏、全显与反复切换；几何结果不能代替视觉验收。

经用户明确许可，做了两次仅顶部菜单栏、无音频的 25 秒录屏。基础路径复现短暂插入重叠；预留空位实验虽能移动，但导致额外位移和延迟，已撤回，不进入预览源码。录屏与拆帧图分析后均已删除，未上传个人录像或原始诊断。本版不宣称完整功能矩阵全部通过、动画重叠已解决或达到 iBar 的顺滑程度；刘海、多屏、其他系统、原菜单边界与更广泛回归仍待完成。
