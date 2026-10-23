## 下载安装 / Download

**[下载 DMG（推荐） / Download DMG](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.10/DrawerBar-0.1.10-AppleSilicon.dmg)** · **[下载 ZIP / Download ZIP](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.10/DrawerBar-0.1.10-arm64.zip)**

Apple Silicon（M1 或更新）· macOS 14+ · **预览版 / Developer preview**。当前未经过 Apple 公证，已知限制见下文。

If the Assets section stays on “Loading”, use the direct links above. 如果底部 Assets 一直显示 Loading，请直接点击上面的下载链接。

---

# DrawerBar / 小屉 0.1.10 — Bilingual Developer Preview

**English** · 简体中文 below

DrawerBar gives your Mac menu bar a drawer for less-used icons. This preview introduces English and Simplified Chinese across the app, menus, errors, accessibility labels, app display name, and capture explanation.

## Download and install

- `DrawerBar-0.1.10-AppleSilicon.dmg`: open it, drag the app to Applications, eject the image, and open the installed copy.
- `DrawerBar-0.1.10-arm64.zip`: extract and move the app to Applications.
- `SHA256SUMS.txt`: compare downloaded file hashes using `shasum -a 256 <downloaded-file>`.
- Requires an Apple Silicon Mac (M1 or newer), macOS 14+. Actual native checks were on M1 / macOS 26.6.2 / one non-notched display.

Ad-hoc signed; **not Developer ID signed or Apple notarized**. Read [Apple's guidance](https://support.apple.com/102445) if macOS blocks the preview. Accessibility is required to move/use icons; Screen Recording is optional for original icon artwork. Each user authorizes their own installed copy. Rebuilds may require refreshing stale permission records.

Click icons in Organize Icons to hide/show. Click the menu bar drawer or press **⌘⇧Space** to open the single-row drawer. English and Chinese follow macOS app language preferences; the Chinese name is 小屉. Full instructions: [English](../README.md) / [简体中文](../README.zh-CN.md).

## Validation and known issues

14 core check groups and a 168-string localization audit passed in both language modes; local arm64 Release and GitHub CI succeeded. Both app languages were opened. 28 logged native base-path moves succeeded on the first attempt, including all-six hidden/shown states. This is partial native coverage, **not completion of the full regression**.

- **Animation overlap remains:** recording reproduced a brief icon overlap during insertion. Experimental pickup/slot-reservation approaches were withdrawn after failing functional or visual checks. They are absent from this release.
- **Spacing:** preset selection saves immediately; macOS 26 running apps need reopening before their icons adopt it. Reopening is restricted to explicitly selected apps with opt-in. No forced quit or logout. Instant adoption without reopening is not implemented.
- Notch, multiple displays, other macOS versions, original-menu edge cases, and broader native recovery/shortcut/sorting regression remain unverified for this binary. There is no automatic updater.

## 简体中文

小屉为 Mac 菜单栏提供单行抽屉。本预览版新增完整英文与简体中文资源，覆盖产品名、界面、菜单、错误、辅助标签与录屏说明。

下载 DMG 后把应用拖到“应用程序”，推出映像再打开；或解压 ZIP 后移到应用程序。支持 Apple Silicon（M1 或更新）与 macOS 14+，实机环境仅 M1、macOS 26.6.2、单屏无刘海。可用 `shasum -a 256 下载文件` 核对 SHA256SUMS.txt。

当前为临时签名，**没有 Developer ID 签名或 Apple 公证**。系统拦截时先核对来源，再参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。辅助功能用于移动与操作图标，屏幕录制为可选原图像权限；每位用户需在自己的 Mac 授权，重编译可能使旧记录失配。

在“图标整理”点击收起 / 显示，点击菜单栏抽屉或按 **⌘⇧Space** 展开。中文名“小屉”，英文名“DrawerBar”，支持 macOS 应用专属语言设置。完整说明见[中文 README](../README.zh-CN.md)。

14 组核心检查、168 条语言资源审计、arm64 Release 与 GitHub CI 通过；已实际打开两种语言。基础路径 28 条真实移动记录均一次成功，包含六项全藏全显。**这不代表完整实机矩阵全部通过。**

- 动画插入重叠仍存在；录屏已复现。若干拾取 / 预留空位实验未通过功能或视觉检查，已撤回，不包含在此版。
- 间距选中立即保存，但 macOS 26 已运行应用需要重开后采用。仅在主动允许并明确勾选后重开，不强退、不注销；尚未实现免重开的即时更新。
- 刘海、多屏、其他系统、原菜单边界，以及更广泛的恢复 / 快捷键 / 排序回归仍待验收，无自动更新。
