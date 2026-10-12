#!/bin/zsh
set -eu
cd "$(dirname "$0")"
APP="build/AppDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
if [[ ! -f build/AppIcon.icns ]]; then
  swiftc -module-cache-path build/module-cache MakeIcon.swift -framework AppKit -o build/make-icon
  build/make-icon
fi
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path build/module-cache \
  Sources/Core.swift Sources/Storage.swift Sources/Accounts.swift Sources/Library.swift Sources/DevicesView.swift Sources/DeviceSave.swift Sources/App.swift -framework SwiftUI -framework AppKit -framework Security \
  -o "$APP/Contents/MacOS/IPAOrganizer"
clang -O2 -Wall -Wextra Helpers/auth.c -o "$APP/Contents/MacOS/appdock-auth"
codesign --force --sign - "$APP/Contents/MacOS/appdock-auth"
clang -O2 -Wall -Wextra Helpers/wallpaper.c -o "$APP/Contents/MacOS/appdock-wallpaper"
codesign --force --sign - "$APP/Contents/MacOS/appdock-wallpaper"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>IPAOrganizer</string>
<key>CFBundleIdentifier</key><string>local.ipashelf.mac</string>
<key>CFBundleName</key><string>AppDock</string>
<key>CFBundleDisplayName</key><string>AppDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>2.1</string>
<key>CFBundleVersion</key><string>13</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp catalog/apps.json "$APP/Contents/Resources/app-catalog.json"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
ditto Licenses "$APP/Contents/Resources/Licenses"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "$PWD/$APP"
