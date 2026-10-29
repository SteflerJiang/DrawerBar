# Privacy / 隐私

No accounts, network requests, analytics, telemetry, advertisements, cloud storage, or automatic update checks are implemented. Icon captures are requested for menu bar icon artwork, processed in memory, and not written to image files or transmitted. When the drawer opens, the app also samples a narrow strip of the menu bar on that display to match its background. A per-row median removes glyph detail; only a one-pixel-wide color strip stays in memory. This sample is not saved or uploaded. The Screen Recording permission is optional; system material and app artwork are the fallback.

Accessibility is required for identifying and moving menu bar icons and invoking their original actions. macOS grants a broad permission; the application's intended use is restricted to menu bar management. Mouse event taps support the legacy native-movement path. On macOS 27, context actions unavailable through Accessibility and modified clicks can use one verified native mouse invocation; the pointer is restored afterward. This does not inject keyboard events. Global shortcuts use Carbon registration and passive observers for shortcuts/Esc; no active keyboard event tap intercepts or reposts ordinary keys. Typed text is not logged. This is not a sandboxed App Store application.

Local data: `~/Library/Application Support/MenuBarStudio/`.

- `configuration.json`: categories, drawer order, onboarding state, delay/shortcut, spacing backups, and selected apps for reopening. Saved atomically with mode 0600.
- `configuration-unreadable-*.json`: preserved unreadable configuration backups.
- `configuration-before-reset.json`: the pre-reset arrangement backup.
- `last-check.json` and `diagnostic-history.jsonl`: current/bounded diagnostic history (up to 200 entries), including source app identifiers, action types, geometry, timing and original-menu item counts. No screenshots, menu body text, or typed characters. These are local, but can reveal installed/running apps. Review before sharing.
- System preferences: current-user/current-host spacing and padding. macOS owns Accessibility, capture, login item, and preferred language records.
- On macOS 27, ordering requires selecting `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`. A security-scoped bookmark is retained in app preferences. Only entrance/target ordering values are changed; the live ordering table is backed up as `native-layout-original-table.plist` in the local data directory before the first write. The backup contains app identifiers and ordering values. Quitting releases the temporary visibility restriction; intentional ordering changes remain saved.

没有账号、联网请求、分析、遥测、广告、云存储或自动更新检查。原图标按需截取、内存处理，不保存图片、不上传。展开浮栏时，还会在所在显示器的菜单栏上做窄条颜色采样，逐行取中值，只在内存中保留一像素宽的颜色条，用于匹配背景；不保存、不上传。不允许录屏时使用系统材质及应用图标。

辅助功能用于识别、移动及操作菜单栏项目。系统授予的权限本身较广，本工具的用途限于菜单栏管理。旧版移动路径使用鼠标事件监听；macOS 27 对没有辅助功能菜单动作的应用和带修饰键的点击，可使用一次经过位置核对的原生鼠标调用，随后恢复鼠标位置，不发送键盘事件。快捷键通过 Carbon 注册与被动观察处理，不主动拦截或重新投递普通按键，不记录输入文字；应用不是沙盒 App Store 程序。

本机配置、恢复备份和有限诊断位于上述目录；诊断会透露应用标识等信息，公开前需要检查脱敏。系统权限、登录项和语言记录由 macOS 管理。退出时不会自动删除配置或恢复用户主动设置的间距。

macOS 27 排序需要用户选择上述 `com.apple.MenuBar.plist` 文件，并在应用偏好中保存安全作用域书签。只调整入口和目标应用的排序值；首次写入前，在本地数据目录保存 `native-layout-original-table.plist` 实时排序表备份，其中含应用标识与排序数据。退出会解除临时隐藏限制，主动调整的顺序会保留。
