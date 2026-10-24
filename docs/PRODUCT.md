# Product scope / 产品范围

## Purpose / 目标

DrawerBar (小屉 in Simplified Chinese) is a focused, local menu bar organizer for Apple Silicon Macs. It gives less-used app icons a single-row drawer while leaving frequently used icons accessible in the menu bar. The first release favors clear categories, predictable original app actions, and recoverable changes.

小屉面向 Apple Silicon Mac，为不常用图标提供单行浮栏；常用图标保留在菜单栏。精简首版优先保证分类清晰、原生操作可用、修改可恢复。

## Core flows / 核心流程

1. **Welcome → permissions → hide and recover one icon.** Accessibility required, Screen Recording optional. The guide can be skipped and reopened. / 引导、权限、真实收起并找回一个图标，可跳过和重新查看。
2. **Organize:** two visible groups, one click to change category, cross-group drag, saved drawer ordering. New icons start visible. Real position confirmation precedes category persistence. / 双区整理、一键切换、跨区拖动、浮栏排序；新项目默认常驻，实际移动确认后保存。
3. **Drawer:** template drawer entry left of managed visible icons; all hidden icons in one row, horizontal overflow only. Original left/right actions, pin, settings, outside click, Esc, and delayed closing. / 空心抽屉入口位于受管常驻图标左侧；隐藏项目单行，超宽横向滚动；原点击、右键、固定、设置与自动关闭。
4. **Appearance:** four spacing presets with preview, backup, undo, and restore. Distinguish a saved preference from appearance adoption; app reopening requires explicit selection and opt-in. / 四档间距、预览、备份、撤销与恢复，区分保存和外观生效，明确选择并授权后才重开来源应用。
5. **General:** global shortcut with conflict feedback, close delay, launch at login, system appearance, arrangement reset. / 全局快捷键与冲突提示、收起延时、登录启动、系统外观与整理重置。
6. **Recovery:** pause/normal quit releases hidden items; permission changes and source replacement must preserve intended rules. / 暂停与正常退出释放隐藏项，权限变化和来源重建时保留用户规则。

## Design constraints / 设计约束

- Clear icon contrast; full uncropped glyphs; keyboard/accessibility labels. / 图标对比清楚、不裁切、有键盘和辅助标签。
- Ordinary category/spacing changes have no second confirmation. Resetting categories does. / 常规分类与间距操作无需二次确认，清空分类需要确认。
- Move only the target icon; do not unfold the whole hidden region to perform an ordinary move. / 常规移动仅操作目标，不整体展开隐藏区。
- English and Simplified Chinese share one app, configuration and internal identifier. / 中英文共用应用、配置与内部标识。
- Do not report a UI selection as proof that the real icon moved. / 不能以界面勾选代替真实图标位置验证。

## Out of scope / 当前不做

No accounts, cloud sync, subscriptions, telemetry, automatic updates, Windows/Linux/Intel release, system-icon automation, guaranteed notch recovery, or universal multi-display certification. Instant spacing without reopening apps remains unresolved. No claim of iBar-equivalent smoothness or zero flicker is made without frame evidence.

当前不包含账号、云同步、订阅、遥测、自动更新、Windows/Linux/Intel 发布或系统图标自动整理；未保证刘海后找回和全多屏兼容。不重开应用的即时间距尚未实现；没有逐帧证据前不宣称与 iBar 一样顺滑或绝不闪动。


## Native reorder transactions / 原生图标移动事务

On the tested macOS 26 Control Center host, a transaction posts each intended event to WindowServer once. Native event delivery and position checks run off the UI thread, so settings layout and Accessibility queries cannot stall a held drag. App-owned windows on other systems retain the compatibility route.

A hidden item is picked up below the active display. The hover stage addresses the intended insertion neighbor while the glyph remains offscreen. Before release, the transaction checks that the drawer artwork has cleared the complete destination width and the right neighbor stayed in place. It then drops the source into the first visible slot. System items are read-only boundaries. The hidden divider does not expand for an ordinary classification change.

The saved category changes only after two valid native position observations. An already-correct placement waits for confirmation instead of replaying a drag merely because a polling deadline passed. Retries remain bounded for actual delivery or placement failures. Cancellation releases any held drag and restores the cursor. Verification is scoped to the OS/host combination tested; it is not an assertion of compatibility with every display or macOS release.

在实测的 macOS 26 Control Center 托管路径中，每个目标事件仅向 WindowServer 投递一次；原生事件与位置校验在界面线程之外执行，避免设置布局和辅助功能查询拖住移动过程。其他系统的应用自有窗口保留兼容路径。

显示隐藏图标时，先在屏幕下方拾取目标，再将悬停事件指向预期插入邻居。图案仍在屏外时，确认抽屉图案已让出完整目标宽度，且右侧邻居没有被推走，再放下图标。新显示项目位于入口右侧第一位；系统图标仅作为只读边界，常规分类切换不展开整片隐藏区。

连续两次真实位置校验通过后才保存分类。已经位于正确位置的项目继续等待确认，避免仅因一次轮询超时而重新拖动；实际投递或位置失败仍有有界重试。取消事务会释放尚未结束的拖动并恢复鼠标。实现按已测试的系统与宿主限定启用，不代表所有屏幕和系统均已通过兼容性验收。
