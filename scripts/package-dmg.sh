#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
DELIVERABLES="${BUILD_OUTPUT_DIR:-${PROJECT_ROOT:h}/outputs}"
APP_NAME="${APP_BUNDLE_NAME:-小屉}"
APP_PATH="${DELIVERABLES}/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    print -u2 '请先运行 zsh scripts/build.sh 构建小屉.app'
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
DMG_PATH="${DELIVERABLES}/${APP_NAME}-${APP_VERSION}-AppleSilicon.dmg"
STAGING_DIR=$(/usr/bin/mktemp -d "${DELIVERABLES}/.xiaoti-dmg.XXXXXX")
trap '/bin/rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/bin/cp "$PROJECT_ROOT/docs/INSTALL.txt" "$STAGING_DIR/INSTALL.txt"
/usr/bin/hdiutil create -quiet -volname "DrawerBar ${APP_VERSION} Preview" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDZO -ov "$DMG_PATH"
/usr/bin/hdiutil verify -quiet "$DMG_PATH"
print "$DMG_PATH"
