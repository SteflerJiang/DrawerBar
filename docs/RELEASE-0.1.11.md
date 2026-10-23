# DrawerBar / 小屉 0.1.11 — Native Drawer & System Boundaries

**[Download DMG / 下载 DMG](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.11/DrawerBar-0.1.11-AppleSilicon.dmg)** · **[Download ZIP / 下载 ZIP](https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.11/DrawerBar-0.1.11-arm64.zip)**

Apple Silicon (M1 or newer), macOS 14+. Developer preview, ad-hoc signed, not Apple notarized.

## English

- **Native drawer appearance:** background colors follow a narrow sample of the actual menu bar. Original status icons retain their point sizes and proportions, including wide traffic meters and unread counts. Individual icon-card backgrounds and borders are removed.
- **Compact empty state:** click the entire row once to open Organize Icons.
- **System boundary fix:** visible apps such as SSRUN insert before Input, Battery, and other read-only system anchors. Idle synchronization detects apps crossing into that group even when their visible/hidden category has not changed. Only the app is moved back; system items are not moved. The OS capture/privacy indicator is excluded from discovery and ordering.

### Install and use

Open the DMG, drag DrawerBar.app to Applications, eject the image, and launch the installed copy. Or extract the ZIP into Applications. Quit an older copy before replacing it. Grant Accessibility for icon movement; Screen Recording is optional for original icons and matching menu-bar colors. Each Mac authorizes its own copy. Read [Apple's guidance](https://support.apple.com/102445) if macOS blocks the unnotarized preview. Verify downloads with `shasum -a 256 <file>` and SHA256SUMS.txt. Click an icon in Organize Icons to hide/show; click the menu-bar drawer or press **⌘⇧Space** to open it. [Full English guide](https://github.com/SteflerJiang/DrawerBar/blob/v0.1.11/README.md).

### Validation and remaining limits

Fifteen core check groups passed in English and Chinese; the 168-string audit and arm64 Release build passed. The styled binary was inspected on M1 / macOS 26.6.2 / one non-notched display with zero, one, a wide SSRUN item, and all six hidden icons. Pinning, drawer closing and the one-click empty action were checked. Flux's original context menu opened; the user closed it when Computer Use could not target that menu-only application. Original configuration and the idle controller were verified afterward.

The preceding ordering candidate had 22 first-attempt successful moves; those records are not a new 22-move regression of the later styled binary. No new frame-by-frame smoothness certification is claimed. Previous insertion overlap and spacing adoption requiring source-app reopening remain unresolved. Notch, multiple displays, other macOS versions and the full native test matrix remain unverified. See [testing and scope](https://github.com/SteflerJiang/DrawerBar/blob/v0.1.11/docs/TESTING.md).

## 简体中文

- **菜单栏原样式浮栏**：背景跟随真实菜单栏配色；原始图标保持原尺寸与比例，网速、未读数等宽图标保留宽度。移除图标独立底色和边框。
- **紧凑空状态**：点击提示整行，一次打开图标整理。
- **系统图标边界修复**：SSRUN 等应用显示在输入法、电源等系统参照之前。分类未变时也能发现越界，只将第三方应用移回，系统图标本身不由小屉移动。录屏隐私指示器不参与发现和排序。

### 安装与使用

打开 DMG，将 DrawerBar.app 拖入“应用程序”，推出映像再打开；或解压 ZIP 后移入应用程序。替换前退出旧版本。辅助功能用于移动图标；屏幕录制为显示原图标与匹配背景色的可选权限，每台 Mac 单独授权。本版为临时签名、未经 Apple 公证；若被系统拦截，请核对来源后参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。用 `shasum -a 256 下载文件` 对照 SHA256SUMS.txt。图标整理页点击收起 / 显示，点击菜单栏抽屉或按 **⌘⇧Space** 展开。[完整中文说明](https://github.com/SteflerJiang/DrawerBar/blob/v0.1.11/README.zh-CN.md)。

### 验证与现有限制

15 组中英文核心检查、168 条语言审计及 arm64 Release 构建通过。样式版在 M1 / macOS 26.6.2 / 单屏无刘海实测空浮栏、单图标、SSRUN 宽图标、六项全藏，并核对固定、收起与空状态一次打开整理页。Flux 原右键菜单已打开，因 Computer Use 无法选中其纯菜单栏应用，由用户关闭；随后确认原配置恢复且控制器空闲。

此前排序候选版完成 22 次一次成功的移动，这不能算作后续样式版重新完成 22 次验收，也不是新的逐帧流畅度证明。既有插入重叠、间距需重开来源应用的限制仍存在；刘海、多屏、其他系统及完整实机矩阵仍待验收。[测试与范围](https://github.com/SteflerJiang/DrawerBar/blob/v0.1.11/docs/TESTING.md)。
