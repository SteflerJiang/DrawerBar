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

In 0.1.10 development, two experimental pickup-coordinate approaches failed the actual placement check. They were withdrawn; ordinary icon movement uses the prior 0.1.9 base path. Further motion/flicker investigation is still open. Do not read the bilingual release as completion of the full native regression.

0.1.10 开发中，两种实验拾取坐标方案均未通过真实位置校验，已撤回；常规移动恢复为 0.1.9 的基础路径。轨迹与闪动仍需进一步调查。双语开源不代表完整实机验收已经完成。

## Known limits / 已知限制

Only a single M1, macOS 26.6.2, non-notched desktop has been available. Multi-display, notched MacBooks, other macOS versions, real login-after-reboot, and energy measurements are not certified. A geometry sample is not a captured frame: it cannot prove that no transient pixel or ghost ever appeared. Never label an unrecorded motion test “flicker-free.”

当前实体环境仅为一台 M1、macOS 26.6.2、单屏无刘海；未完成多屏、刘海、其他系统、重启登录与能耗验收。几何样本不能证明每帧都没有闪动；未录制的移动不能标注“绝不闪动”。

Spacing adoption without source app reopening remains unresolved. Context menus depend on source app behavior. Preview builds are not notarized, and rebuilding may invalidate existing macOS permission records.

免重开的间距即时生效仍未完成，原菜单取决于来源应用，预览版未公证，重新构建可能使旧授权失配。
