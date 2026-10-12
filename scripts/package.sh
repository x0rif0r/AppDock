#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
zsh build.sh
APP="build/AppDock.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"; rm -f "$STAGE-components.plist"' EXIT
mkdir -p "$STAGE/Applications"
ditto "$APP" "$STAGE/Applications/AppDock.app"
codesign --verify --deep --strict "$STAGE/Applications/AppDock.app"
pkgbuild --analyze --root "$STAGE" "$STAGE-components.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$STAGE-components.plist"
pkgbuild --root "$STAGE" --component-plist "$STAGE-components.plist" --identifier io.github.x0rif0r.appdock --version "$VERSION" --install-location / --ownership recommended "dist/AppDock-$VERSION-macOS-arm64.pkg"
(cd dist && shasum -a 256 "AppDock-$VERSION-macOS-arm64.pkg" > SHA256SUMS.txt)
echo "Installer: dist/AppDock-$VERSION-macOS-arm64.pkg"
