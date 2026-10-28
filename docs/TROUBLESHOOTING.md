# Troubleshooting / 常见问题

## Ordering access on macOS 27 / macOS 27 排序授权

The ordering candidate needs the user to select `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist` through its file picker. Use the ordering access button; if the picker does not locate the file, press Command-Shift-G and paste the path. This is a single-file grant, retained as a bookmark. Rebuilding an ad-hoc executable can separately invalidate Accessibility; remove the old entry and add `/Applications/DrawerBar.app` again. Full Disk Access is not requested. Before writing, the app backs up the original plist to `~/Library/Application Support/MenuBarStudio/native-layout-original.plist` and checks for unrelated changes. A saved ordering number alone does not establish success: the app also confirms MenuBarAgent's actual drawn geometry.

排序候选版需要通过文件选择框授权 `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`。点“授权菜单栏排序文件”；未定位时按 ⌘⇧G 输入路径。仅授权这个文件，并保存书签。临时签名构建变化后，辅助功能需要单独移除旧条目并重新添加 `/Applications/DrawerBar.app`。无需授予完全磁盘访问。修改前会备份原文件到 `~/Library/Application Support/MenuBarStudio/native-layout-original.plist`，并核对是否有无关修改。写入排序值后，还必须核对 MenuBarAgent 的实际绘制位置，才会确认操作成功。

If the app reports insufficient menu bar space, hide another icon before showing the target. On a notched display, the entrance and incoming icon must fit in the usable area to the right of the notch. The app checks this before revealing the target and keeps its hidden classification on failure.

若提示菜单栏空间不足，请先收起另一个图标再显示目标。刘海屏上，入口和新显示图标必须容纳于刘海右侧可用区域；应用会在显示前检查，空间不足时保留原隐藏分类。

## No independent status windows on macOS 27 / macOS 27 缺少独立菜单栏窗口

The legacy movement engine requires individual WindowServer status windows. On the local macOS 27.2 system, the app resolved accessibility source frames but WindowServer returned no status-layer windows; the entrance and divider had placeholder identifiers larger than a `CGWindowID`. The macOS 27 backend now uses Accessibility source identities and a temporary MenuBarAgent allow-list. Run the installed copy from `/Applications`; re-add its current binary to Accessibility after rebuilding. Screen Recording does not repair the legacy architecture and is not required for the native allow-list. Missing runtime classes fail closed by leaving icons visible. Consult TESTING.md for the actual native results and the grouped-by-app limitations.

旧移动引擎依赖 WindowServer 的独立菜单栏窗口。本机 macOS 27.2 中，辅助功能可读到来源位置，但系统返回的菜单栏窗口数为零，入口和分隔线的窗口编号为超出 `CGWindowID` 范围的占位值。macOS 27 新后端改用辅助功能来源身份与 MenuBarAgent 临时显示白名单。请从 `/Applications` 运行安装副本，重编译后重新添加辅助功能授权。屏幕录制不能修复旧架构，也不是新白名单的必需权限。系统接口不可用时保持图标可见。实机结果及按应用分组的限制见 TESTING.md。

## Permission enabled but shown as denied / 已开启但显示未授权

Confirm the app path and version. Quit duplicate copies and run the installed copy from Applications. Ad-hoc rebuilds can invalidate trust for the old executable. In System Settings, remove only the stale DrawerBar/小屉 entry, add the current installed app, enable it, and reopen if macOS requests. Complete password or Touch ID prompts yourself. Do not reset all TCC permissions or edit macOS permission databases.

核对路径与版本，退出重复副本，从应用程序打开。临时签名重编译可能让旧记录失效。只移除小屉的旧记录，再添加当前安装副本、开启并按系统要求重开。Touch ID / 密码由本人完成，不要重置全部权限或编辑权限数据库。

## Spacing saved but unchanged / 间距保存后没变化

Running apps may cache spacing. Select only apps you are willing to reopen, or reopen them yourself. DrawerBar does not forcibly quit apps. System icons may not update. See the spacing limits in the README. If another tool changed spacing after DrawerBar's last write, undo stops to avoid overwriting it.

已运行应用可能缓存间距，只选择你允许重开的应用，或自行重开；不强制退出。系统图标不保证更新。其他工具再次修改后，撤销会停止以免覆盖。

## Missing icons or repeated motion / 图标消失或位置反复变化

Use Pause & Show All Icons, refresh, and check Accessibility. Pause other menu bar managers when diagnosing conflicts. Limited space/notches can still prevent all items fitting. Normal quit releases DrawerBar's boundary. Relaunch from Applications to reopen settings. Do not delete settings while the app is still running.

先暂停整理、刷新并检查辅助功能；排查时暂停其他同类管理工具。空间不足 / 刘海仍可能遮挡图标。正常退出会释放小屉边界，重新从应用程序打开可进入设置。不要运行中删除配置。

## Original context menu unavailable / 无法打开原右键菜单

Some apps have no context menu or use a custom implementation. Show the icon in the real menu bar and try there. Include app/version and steps in a bug report, without private menu content.

部分应用没有原右键菜单或采用特殊实现，可先改成常驻再操作。反馈时附来源应用与版本，不上传私密菜单正文。

## Language / 语言

Set an app language under System Settings → General → Language & Region → Applications and reopen. Names in the source application's menu are owned by that application. The installer filename can remain `DrawerBar.app` while Finder displays 小屉.

在系统设置的“语言与地区 → 应用程序”设置应用语言并重开。来源应用菜单的语言由其自身决定。文件名 DrawerBar.app 与 Finder 本地化显示名“小屉”可以同时存在。

## Optional local-data removal / 可选本机数据清理

First restore spacing if wanted, disable launch at login, and quit normally. To start fresh without irreversible deletion, move `~/Library/Application Support/MenuBarStudio/` to a private backup folder using Finder, then reopen. Keep the backup until you confirm the new state. This directory contains app identifiers; do not publish it.

先按需恢复间距、关闭登录时启动并正常退出。需要全新配置时，用 Finder 把上述目录移到私密备份文件夹，再重新打开；确认无误前保留备份。目录包含应用标识，勿公开上传。
