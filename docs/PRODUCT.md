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
