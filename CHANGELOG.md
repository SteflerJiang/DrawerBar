# Changelog / 更新记录

## 0.1.10 — Developer preview / 开发预览

- English product name **DrawerBar**, Chinese **小屉**; 168 translated strings, localized app metadata, permission explanations, menus, errors, and accessibility labels. / 中英文名称与完整语言资源。
- Wider settings sidebar for English navigation. Bilingual setup, installation, usage, privacy, troubleshooting, and contribution documentation. / 适配英文侧栏，补充双语说明。
- Target-only temporary reveal for original menus; sorting, permission recovery, welcome trial, reset backup, explicit spacing relaunch selection, and improved contrast. These behavior changes require the native regression scope documented in TESTING.md. / 原菜单仅临时显示目标项目，并修订排序、权限恢复、引导、恢复备份、间距重开选择及对比度；实机验收范围见测试文档。
- Two experimental pickup-coordinate strategies failed native placement verification and were withdrawn. Motion/flicker regression remains open; ordinary movement retains the 0.1.9 base path. / 两种拾取坐标实验实测失败，已撤回；常规移动保留 0.1.9 基础路径，轨迹与闪动问题仍待验收。
- No instant spacing adoption without reopening cached source apps. No Developer ID signature/notarization yet. / 尚未实现免重开的即时间距，也未完成正式签名与公证。

## 0.1.9 — Prior local build / 历史本机构建

- Kept the hidden boundary constant for ordinary moves. Outline template drawer glyph; no divider artwork. / 常规移动保持隐藏边界固定，透明空心抽屉，无分隔线图像。
- Historical final binary: 36 native moves, all first-attempt success, median 384 ms (129–570 ms); 144 geometry samples detected no region expansion or hidden peer exposure. These are prior-version observations, not frame-by-frame proof or certification of 0.1.10. / 历史最终构建的 36 次操作一次成功，中位 384ms，144 个几何样本未检测到整区展开或同伴露出；不能外推到 0.1.10，也不是逐帧录像证明。
