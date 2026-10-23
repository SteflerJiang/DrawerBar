# Changelog / 更新记录

## Unreleased — Topology scan reduction / 减少重复布局扫描

- Keep the verified topology after a successful classification change. Normalize temporarily omitted hidden windows, and exclude the app's controls and OS capture indicator from idle topology checks. Real observed side changes still override the hidden-window cache. / 成功切换后保留已验证布局；隐藏窗口暂时未列出不再触发重复扫描，小屉控件与系统录屏指示器不参与空闲布局签名；实际观察到的分类变化仍优先处理。
- Add regressions for omitted hidden windows, manual side changes, missing visible windows, and new windows. / 补充隐藏窗口遗漏、真实跨区移动、常驻窗口消失及新窗口的回归检查。
- **Animation overlap and slow native retries remain unresolved.** Four motion experiments failed acceptance and were withdrawn. This is a scan-reduction change, not a completed animation fix or a new downloadable release. / **动画重叠与原生慢重试仍未解决。** 四个动画实验均未通过验收，已撤回。本次仅减少重复扫描，不代表动画修复完成，也不发布新安装包。

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
