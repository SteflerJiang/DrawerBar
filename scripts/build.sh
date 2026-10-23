#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
DELIVERABLES="${BUILD_OUTPUT_DIR:-${PROJECT_ROOT:h}/outputs}"
APP_NAME="${APP_BUNDLE_NAME:-小屉}"
APP_PATH="${DELIVERABLES}/${APP_NAME}.app"
cd "$PROJECT_ROOT"
swift build -c release --arch arm64 --product MenuBarStudio
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/arm64-apple-macosx/release/MenuBarStudio "$APP_PATH/Contents/MacOS/MenuBarStudio.new"
mv -f "$APP_PATH/Contents/MacOS/MenuBarStudio.new" "$APP_PATH/Contents/MacOS/MenuBarStudio"
cp Info.plist "$APP_PATH/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/bin/ditto .build/arm64-apple-macosx/release/MenuBarStudio_MenuBarCore.bundle "$APP_PATH/Contents/Resources/MenuBarStudio_MenuBarCore.bundle"
for language in en zh-Hans; do
    /usr/bin/ditto "Resources/${language}.lproj" "$APP_PATH/Contents/Resources/${language}.lproj"
done
/usr/bin/codesign --force --sign - --identifier local.menubarstudio.app "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
# In-place builds must invalidate the original bundle metadata after adding icons.
/usr/bin/touch "$APP_PATH"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DELIVERABLES/${APP_NAME}-arm64.zip"
echo "$APP_PATH"
