# Changelog / 更新记录

## 0.1.14 — Faster drawer opening / 浮栏快速打开

- Present the shared icon snapshot before scanning, sorting verification or artwork capture. Refresh optional artwork asynchronously; defer stale-snapshot scans until the drawer is closed and idle. / 先显示现有图标，再异步更新图像；过期扫描推迟到浮栏关闭且空闲后，移除点击路径中的扫描与排序等待。
- Cancel stale artwork updates on close/reopen, suppress implicit panel animation, and retain normal click-to-close and Esc behavior. / 关闭与重开时取消过期图像任务，禁用面板隐式动画，保留再次点击和 Esc 关闭。
- Targeted local validation on one M1 / macOS 27.2: 15 opens, window-visible signal 70–89 ms (median 76 ms), empty/one/two-icon drawers, 20 alternating menu-bar clicks, pin/Esc and original configuration restoration. This measures controller-entry to AppKit visibility, not physical input-to-photon latency. See [test scope](docs/TESTING.md). / 单台 M1 / macOS 27.2 实测 15 次打开，可见信号 70–89ms（中位 76ms），空状态、单图标、双图标、20 次连续点击、固定与 Esc、原配置恢复通过；属于控制器入口至 AppKit 可见信号的耗时，不是硬件按下至像素显示延迟。
- Existing preview limits remain: ad-hoc signature, no Apple notarization, private macOS 27 interface, and no newly certified multi-display/notched-Mac coverage. / 保留临时签名、未公证、macOS 27 私有接口等限制，本次未扩展多屏或刘海设备验收。

## 0.1.13 — macOS 27 compatibility / macOS 27 兼容修复

- Use the macOS 27 host’s live ordering preferences instead of competing cache and disk writes. Create the current entrance identity when importing legacy records. Preserve unrelated app and system values. / macOS 27 改用宿主实时排序偏好，避免缓存与磁盘互相覆盖；自动补齐旧配置的当前入口身份，保留无关应用与系统值。
- Keep the entrance leftmost, reserve the incoming slot before reveal, and verify actual adjacent geometry across stable samples. Track rendered app width separately from returning OS modules. / 入口保持靠左，显示前预留空位，再通过稳定的真实几何样本确认紧邻；分别记录应用宽度与系统模块恢复宽度。
- Present the entrance proxy before hiding the original artwork and restore the original before retiring the proxy. / 先呈现入口代理再隐藏原图，交接结束先恢复原图再关闭代理，修复观察到的单帧空缺。
- Remove active keyboard interception. Keep registered Carbon hotkeys and passive observation; user typing no longer duplicates in the confirmed device check. / 移除键盘主动拦截，保留 Carbon 快捷键与被动观察；实机确认普通输入不再重复。
- Migrate imported target identities and admit newly running apps before discovery without releasing existing hidden apps. Context actions without AXShowMenu, including Caffeine Control-click, use one verified native pointer invocation. / 自动迁移目标身份，新应用在发现前加入显示白名单，保留其他隐藏项目；没有 AXShowMenu 的应用通过一次原生鼠标调用打开菜单。
- Shipped binary: dedicated native smoke checks, 22 first-attempt manual placement transactions, a 2,513-frame menu-bar-only sample, native Caffeine context menu/recovery, ordinary input, and cold-start restoration passed on one M1 / macOS 27.2 / single non-notched display. Both release archives contain that exact executable. This remains an ad-hoc signed, unnotarized preview using a private system interface. See [evidence and limits](docs/TESTING.md). / 同一二进制通过专用自检、22 次一次成功的切换、2,513 帧菜单栏样本、原菜单与自动收回、普通输入及冷启动恢复；双安装包均含这一程序。仍为系统私有接口、临时签名且未公证的开发预览版，覆盖限制见测试文档。

## 0.1.12 — Native motion transactions / 原生图标移动修复

- On macOS 26 Control Center-hosted icons, deliver each native drag through WindowServer once. Keep legacy routing for other hosts and macOS versions. / macOS 26 的控制中心托管图标使用单一路由，避免重复投递；其他宿主与系统保留兼容路径。
- Prepare the insertion gap while the picked-up artwork stays offscreen; release the icon only after the drawer outline clears its destination. Preserve the collapsed hidden region. / 在目标图标保持屏外时先让出插入空间，入口图形离开目标位置后再显示图标；不展开整个隐藏区。
- Perform native movement and position confirmation outside the UI actor. Confirm a late successful position rather than replaying an already completed move. Cancel pending mouse-down safely on normal quit. / 移动和位置验证移到界面线程之外；迟到的成功坐标继续确认，不重复拖动；正常退出时释放未完成的鼠标事件。
- Retain verified topology after classification changes; stabilize temporarily omitted hidden windows without suppressing real layout changes. / 保留已验证布局，处理隐藏窗口暂时遗漏，同时继续响应真实布局变化。
- Exact shipped binary: 34 recorded native moves, all first-attempt success; hide 228–488 ms, show 466–739 ms, overall median 473 ms. Reviewed captured transition frames did not reproduce insertion overlap or hidden-peer flashes on the tested M1 / macOS 26.6.2 / single non-notched display. Original right-menu opening and post-Esc target recovery also passed. See [test scope](docs/TESTING.md); this is not certification of other desktops. / 同一发布二进制的 34 次录屏实测均一次成功；当前设备未复现插入重叠或隐藏同伴闪出，原右键菜单打开及 Esc 后自动收回通过，范围见测试文档。
- Rename the source artwork to `Assets/AppIcon.png` and consolidate both installation languages into `docs/INSTALL.txt`. Keep the Chinese README and localized product name. / 统一素材与安装说明文件名，保留中文 README 和产品本地化名称。
- Instant spacing adoption without source-app reopening and Apple notarization remain open. / 免重开的即时间距和 Apple 公证仍未完成。

## 0.1.11 — Native drawer and system boundaries / 原样式浮栏与系统边界修复

- Include system and unmanaged status items when choosing and verifying the first shown slot. A lone visible application must stay before Input, Battery, and other system extras. / 显示图标时同时检查系统与未托管项目；仅有一个常驻应用时，也不能插入输入法、电源等系统图标之间。
- Detect a visible application crossing the protected group even when its hidden/visible classification has not changed; repair only the application. System items remain read-only anchors. / 可见分类不变时仍检查越界，只修复第三方应用位置，系统图标作为只读参照。
- Exclude the OS-owned capture/privacy indicator from discovery and ordering. Its fixed position must not cause repeated repairs or be mistaken for another app. / 系统录屏隐私指示器不参与发现与排序，避免误认应用及重复修复。
- Drawer colors follow a narrow sample of the real menu bar. Original icons use native dimensions, including wide meters; individual card backgrounds and borders are removed. A compact empty row opens Organize Icons in one click. / 浮栏跟随真实菜单栏配色，原始图标按原尺寸展示，保留宽图标，移除单独底色与边框；空状态缩小为一键打开整理页的紧凑入口。
- This targeted fix does not resolve the previously documented animation-overlap and instant-spacing limitations. See TESTING.md for the actual native scope. / 此次修复不代表已解决既有动画重叠与即时间距限制，实测范围见测试文档。

## 0.1.10 — Developer preview / 开发预览

- English product name **DrawerBar**, Chinese **小屉**; 168 translated strings, localized app metadata, permission explanations, menus, errors, and accessibility labels. / 中英文名称与完整语言资源。
- Wider settings sidebar for English navigation. Bilingual setup, installation, usage, privacy, troubleshooting, and contribution documentation. / 适配英文侧栏，补充双语说明。
- Target-only temporary reveal for original menus; sorting, permission recovery, welcome trial, reset backup, explicit spacing relaunch selection, and improved contrast. These behavior changes require the native regression scope documented in TESTING.md. / 原菜单仅临时显示目标项目，并修订排序、权限恢复、引导、恢复备份、间距重开选择及对比度；实机验收范围见测试文档。
- Two experimental pickup-coordinate strategies failed native placement verification and were withdrawn. Motion/flicker regression remains open; ordinary movement retains the 0.1.9 base path. / 两种拾取坐标实验实测失败，已撤回；常规移动保留 0.1.9 基础路径，轨迹与闪动问题仍待验收。
- No instant spacing adoption without reopening cached source apps. No Developer ID signature/notarization yet. / 尚未实现免重开的即时间距，也未完成正式签名与公证。

## 0.1.9 — Prior local build / 历史本机构建

- Kept the hidden boundary constant for ordinary moves. Outline template drawer glyph; no divider artwork. / 常规移动保持隐藏边界固定，透明空心抽屉，无分隔线图像。
- Historical final binary: 36 native moves, all first-attempt success, median 384 ms (129–570 ms); 144 geometry samples detected no region expansion or hidden peer exposure. These are prior-version observations, not frame-by-frame proof or certification of 0.1.10. / 历史最终构建的 36 次操作一次成功，中位 384ms，144 个几何样本未检测到整区展开或同伴露出；不能外推到 0.1.10，也不是逐帧录像证明。
