# DrawerBar · 小屉

[简体中文](README.zh-CN.md) · **English**

**[Download DMG](<https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.12/DrawerBar-0.1.12-AppleSilicon.dmg>)** · **[Download ZIP](<https://github.com/SteflerJiang/DrawerBar/releases/download/v0.1.12/DrawerBar-0.1.12-arm64.zip>)** · [v0.1.12 preview notes](https://github.com/SteflerJiang/DrawerBar/releases/tag/v0.1.12)

A small drawer for your Mac's menu bar. Keep everyday icons visible and tuck less-used ones into a single-row drawer.

Native SwiftUI + AppKit. Built for Apple Silicon. English and Simplified Chinese. No account, telemetry, cloud service, or third-party runtime dependencies.

**Developer preview:** the source targets macOS 14+. Device testing has been on one M1 Mac running macOS 26.6.2, with one display and no notch. Other OS versions, notched displays, and multi-display behavior are not certified. See [testing and limitations](docs/TESTING.md).

## Download

The current developer preview is **v0.1.12**. Use the **Download DMG / Download ZIP** links above, or visit its [release page](https://github.com/SteflerJiang/DrawerBar/releases/tag/v0.1.12). If GitHub’s Assets section stays on “Loading”, the direct links above bypass that section. GitHub’s automatic “Source code” archives contain source, not an installable app. You can also [build from source](#build-from-source).

Previews use an ad-hoc signature. They are **not Developer ID signed or notarized by Apple**. Do not assume CI build success means native interaction tests passed. There is no automatic updater, App Store distribution, Homebrew cask, or Intel build.

## Install

1. Use an Apple Silicon Mac (M1 or newer) with macOS 14 or later.
2. Open the DMG and drag **DrawerBar.app** to **Applications**. For a ZIP, extract it and move the app to Applications. Finder may display the localized name **小屉** in Chinese.
3. Eject the disk image and open the copy in Applications. Keep one installed copy; quit an older copy before replacing it.
4. If macOS blocks this unnotarized preview, review its source, origin, release notes, and checksum first. If you choose to trust it, use **System Settings → Privacy & Security → Open Anyway**, as described by [Apple](https://support.apple.com/102445). Managed Macs may prohibit this. Do not disable Gatekeeper or SIP.
5. Grant **Accessibility** in **System Settings → Privacy & Security → Accessibility**. This is required to identify, move, and invoke other apps' menu bar icons.
6. **Screen Recording** (called Screen & System Audio Recording on some releases) is optional. It supplies the original icon artwork; without it, app icons are used. Grant it only if you want that feature. macOS may ask you to quit and reopen the app.

Each user must grant permissions on their own Mac. A different ad-hoc build may require refreshing an old permission record; an enabled toggle alone does not prove macOS trusts the current executable. See [troubleshooting](docs/TROUBLESHOOTING.md).

## Use

- **Organize Icons:** click an icon to switch between **In the Menu Bar** and **In the Drawer**, or drag between groups. New icons stay visible by default. System items are managed in macOS System Settings.
- **Open the drawer:** click DrawerBar's outline drawer icon in the menu bar, or press **⌘⇧Space**. Hidden icons stay in a single row. If they exceed the screen's available width, scroll horizontally; they do not wrap.
- **Use an icon:** left-click for its original action; right-click for its original context menu when the source app supports one. The current source temporarily brings only that target into the menu bar and returns it after its menu closes. Failure leaves an actionable error rather than silently saving a wrong category.
- **Drawer order:** drag hidden icons within the drawer group. The context menu also offers **Move Earlier / Move Later**. To reorder visible menu bar icons, use macOS **Command-drag**.
- **Close:** press Esc, click outside, or move the pointer away and wait for the configured delay (default 1.5 seconds). The pin keeps the drawer open. Using an original app menu suspends automatic closing.
- **Right-click DrawerBar:** open settings, pause or resume organization, show the welcome guide, or quit. Pause temporarily shows icons while preserving their categories. Normal quit releases the hidden boundary.
- **General:** choose **⌘⇧Space**, **⌘⇧B**, or Off. A shortcut conflict is reported. Enable launch at login if wanted. The interface follows system light/dark appearance.
- **Reset Icon Arrangement:** confirmation is required because it clears categories and drawer order. Spacing, keyboard shortcut, and login preference remain unchanged. A local pre-reset backup is kept.

### Drawer appearance

With Screen Recording access, the drawer matches the menu bar's background colors and displays original status icons at their native point sizes. Wide items, such as traffic meters and unread counts, retain their width. Icons have no separate card fill or border. Without capture access, system material and app artwork are used. An empty drawer is a compact row; click it once to open Organize Icons.

### Icon movement

On macOS 26, Control Center-hosted icons use a single native event route. Showing an icon first makes room beside the drawer, then reveals the target in the first visible slot. Hiding an icon keeps the rest of the hidden region collapsed. The 0.1.12 device regression completed 34 first-attempt moves; inspected recorded transitions did not reproduce the reported overlap or flash. See [measurements and tested scope](docs/TESTING.md). Other macOS versions and hosts retain the compatibility path.

### Spacing

Choose **System Default**, **Comfortable**, **Compact**, or **Minimal**. Selecting a preset saves immediately, with no Apply button or second confirmation. **Undo Last Change** and **Restore System Default** are available.

**Saving is not the same as immediate visual application.** macOS 26 caches spacing in running apps. Their icons update after their owning apps reopen. You can explicitly select apps and opt into reopening those apps when a preset changes. Reopening can interrupt work or connections; no app is force-quit and no logout occurs. Fresh configurations do not preselect apps. System items may retain system-controlled spacing. “Minimal” does not guarantee zero gap. Instant updates without reopening apps are not implemented.

This changes the current user's current-host `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` preferences. Previous values, including an unset value, are backed up. Undo detects intervening changes from other tools and refuses to overwrite them silently. Spacing persists when DrawerBar quits; restore it before uninstalling if desired.

### Language and product name

The same app uses **小屉** in Simplified Chinese and **DrawerBar** in English. UI text, menus, help, errors, accessibility labels, app display name, and the screen-capture explanation are localized. Other languages fall back to English. Source app names and their original menus remain in those apps' own language.

Follow your macOS language preferences, or choose an app-specific language in **System Settings → General → Language & Region → Applications → + → DrawerBar → English / 简体中文**, then reopen the app. The download filename remains DrawerBar so links work worldwide. Existing configurations and the internal bundle identifier are preserved.

## Privacy

Icon images and a narrow menu-bar color sample are processed in local memory, not saved or uploaded. There is no networking, account, telemetry, or automatic update code in the app. Accessibility and capture permissions are macOS permissions, not cloud access.

Configuration and bounded local diagnostics are stored in `~/Library/Application Support/MenuBarStudio/`. The legacy directory and bundle ID `local.menubarstudio.app` are intentionally retained for existing users. Diagnostics can contain app identifiers, window geometry, timing, and action types. They exclude screenshots, menu text, and typed text. Review and redact diagnostic files before sharing them publicly. See [privacy details](docs/PRIVACY.md).

## Update or uninstall

Quit DrawerBar, replace the app in Applications, and reopen it. If permission status changes, follow the troubleshooting guide rather than resetting all macOS permissions.

To uninstall: restore default or previous spacing if wanted, turn off launch at login, quit DrawerBar normally, and move it to Trash. Optional local configuration removal is described in [troubleshooting](docs/TROUBLESHOOTING.md). Other apps' data is not removed.

## Build from source

Requirements: an Apple Silicon Mac, macOS 14+, and a **Swift 6** toolchain (Xcode or compatible Command Line Tools). No package dependencies to install.

```sh
git clone https://github.com/SteflerJiang/DrawerBar.git
cd DrawerBar
swift run CoreChecks
python3 scripts/check-localizations.py
APP_BUNDLE_NAME=DrawerBar zsh scripts/build.sh
APP_BUNDLE_NAME=DrawerBar zsh scripts/package-dmg.sh
```

By default, outputs go to the repository's sibling `outputs/` directory. `BUILD_OUTPUT_DIR` overrides this location. Local builds default to a `小屉.app` filename; `APP_BUNDLE_NAME=DrawerBar` uses the international filename. The executable and bundle ID remain stable. The DMG script packages the existing app without recompiling it.

CoreChecks never writes system spacing preferences. CI builds and checks resources on macOS; native menu bar behavior still requires an unlocked real desktop, permissions, and manual/device regression. A source build is ad-hoc signed; rebuilding may change permission trust.

## Development

- `Sources/MenuBarCore`: configuration, layout policies, localized labels, and resource catalogs.
- `Sources/MenuBarStudio`: application lifecycle, UI, menu bar operations, original menus, global shortcut, spacing preferences, and selected-app reopening.
- `Resources`: localized app metadata and permission explanation.
- `Tests/MenuBarCoreTests`: executable core checks.
- `scripts`: build, DMG packaging, and localization audit.

Read [CONTRIBUTING](CONTRIBUTING.md), [SECURITY](SECURITY.md), [testing](docs/TESTING.md), and [CHANGELOG](CHANGELOG.md). Bug reports should include the version, macOS version, display/notch setup, permission state, and reproducible steps. Never include credentials or unredacted personal screenshots.

## License and acknowledgments

[MIT](LICENSE). Original application artwork was generated for this project; the small menu bar glyph is drawn in code. Apple frameworks and SF Symbols remain subject to Apple's terms.

Product research included iBar's publicly visible behavior and Ice's public implementation concepts for event routing. No iBar assets or Ice source files are bundled. These projects are independent and do not endorse DrawerBar. See [acknowledgments](ACKNOWLEDGMENTS.md).
