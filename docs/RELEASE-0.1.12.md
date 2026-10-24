# DrawerBar / 小屉 0.1.12 — Native motion preview

[Download DMG](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.12/DrawerBar-0.1.12-AppleSilicon.dmg) · [Download ZIP](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.12/DrawerBar-0.1.12-arm64.zip) · [Checksums](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.12/SHA256SUMS.txt)

## English

This preview replaces native movement for macOS 26 Control Center-hosted icons. A single WindowServer event route avoids duplicate drag delivery. The insertion gap opens before the target artwork becomes visible; movement and confirmation run outside the UI actor. A late successful position is confirmed rather than dragged again. Other hosts and macOS versions retain the legacy route.

The shipped binary completed 34 recorded hide/show moves on an M1 / macOS 26.6.2 / single non-notched Retina display, all on the first attempt. Hide: 228–488 ms; show: 466–739 ms; median overall: 473 ms. Captured transition review did not reproduce insertion overlap or hidden-peer flashes. Original right-menu opening, automatic target recovery after the user pressed Esc, shortcut open/Esc close, cold start, 19 core check groups in both languages, and 168-string localization audit passed. See [exact coverage and limits](TESTING.md).

Installation: open the DMG, drag DrawerBar.app to Applications, eject the image, then open the installed copy. Quit an older copy before replacing it. Accessibility is required; Screen Recording is optional for original artwork. Each Mac needs its own permission grants. Rebuilt ad-hoc binaries may need an existing permission record refreshed.

**Developer preview, Apple Silicon only, source target macOS 14+. Ad-hoc signed, without Developer ID or Apple notarization.** Other systems, notched displays, and multiple displays are not certified. Instant spacing changes without reopening cached source apps remain unresolved. [Full installation and usage](../README.md).

The source artwork is now `Assets/AppIcon.png`; bilingual installation instructions are consolidated in `docs/INSTALL.txt`. Chinese UI and README remain available.

## 简体中文

本版重做 macOS 26 控制中心托管图标的移动机制：通过单一 WindowServer 路由投递，在目标图标保持屏外时先让出空间，入口移开后再显示；移动与位置校验不再阻塞界面。已成功但稍晚到达的位置继续确认，避免重复拖动。其他系统及宿主保留兼容路径。

同一发布二进制在 M1 / macOS 26.6.2 / 单屏 Retina 无刘海环境完成 34 次录屏切换，全部一次成功。隐藏 228–488ms，显示 466–739ms，总体中位 473ms；检查的连续过渡帧未复现入口重叠或隐藏同伴闪出。原右键菜单打开、用户按 Esc 后自动收回、快捷键展开与 Esc 收起、冷启动、19 组双语核心检查和 168 条语言审计通过。详见[实测范围](TESTING.md)。

安装：打开 DMG，把 DrawerBar.app 拖入“应用程序”，推出映像，从安装副本打开。更新前退出旧版本。需辅助功能权限；录屏权限为可选，用于原图标。每台 Mac 单独授权，临时签名重编译后可能需要更新旧权限记录。

**仍为 Apple Silicon 开发预览，源码面向 macOS 14+，临时签名，未做 Developer ID 签名与 Apple 公证。** 其他系统、刘海和多屏尚未验收；免重开的即时间距仍未完成。[完整安装和使用](../README.zh-CN.md)。

素材和安装说明统一英文文件名，保留中文界面与中文 README。临时录屏、个人配置和诊断均不进入源码或安装包。

Executable SHA-256 / 程序哈希：`c1dc0b4da2f0596529b0eb563bf2614253783809387dc1b25b6091b7f224ea26`。
