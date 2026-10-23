# Contributing / 参与贡献

English and Simplified Chinese issues and pull requests are welcome.
欢迎使用中文或英文提交 Issue / Pull Request。

1. Describe one reproducible problem, including app version, macOS version, Apple chip, display count/notch, and permission status. Remove personal data. / 描述可复现问题与环境，删除个人数据。
2. Keep changes focused. Preserve existing configuration keys and the bundle identifier unless a migration is included. / 保持改动集中，兼容旧配置；修改标识时提供迁移。
3. Run `swift run CoreChecks`, `python3 scripts/check-localizations.py`, and an arm64 release build. These do not replace native interaction testing. / 运行核心检查、语言资源检查和 Release 构建，实机交互需要另测。
4. Update both `en` and `zh-Hans` string catalogs and both READMEs when behavior changes. Keep placeholders intact. Do not translate source app names or identifiers. / 行为变化同步两种语言，保留占位符，不翻译来源应用名与标识。
5. Test real icon moves, menu actions, permission denial, and recovery on an isolated test desktop before claiming interaction fixes. Never force-quit someone's apps to test spacing. / 真实移动、菜单、拒绝权限与恢复需实测；不要为测试间距强制退出用户应用。
6. Describe exactly what passed and what remains untested. No “flicker-free,” “iBar-equivalent,” or universal compatibility claims without evidence. / 明确已测与未测范围，没有证据不宣称绝不闪动或兼容全部环境。

Contributions are accepted under the repository's MIT license. Do not submit copied proprietary code or assets. If introducing third-party code, document provenance and compatible licensing before inclusion.
贡献遵循 MIT；不要提交未经许可的专有代码或素材。引入第三方代码前说明来源与许可兼容性。
