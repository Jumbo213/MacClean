#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DIST="$PWD/dist"
SIGN_IDENTITY="${MACCLEAN_SIGN_IDENTITY:--}"
mkdir -p "$DIST"
# Swift Package Manager combines both slices into a Universal 2 executable.
swift build -c release --product MacClean --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="$DIST/MacClean.app"
rm -rf "$APP" "$DIST/dmg-stage"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacClean" "$APP/Contents/MacOS/MacClean"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod 755 "$APP/Contents/MacOS/MacClean"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier io.github.Jumbo213.MacClean --timestamp=none "$APP"
else
  codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp "$APP"
fi
codesign --verify --deep --strict "$APP"
if [ -n "${MACCLEAN_NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$MACCLEAN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$DIST/notarize.zip"
fi
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacClean.app"
ln -s /Applications "$STAGE/Applications"
cp docs/安装说明.txt "$STAGE/安装说明.txt"
DMG="$DIST/MacClean-$VERSION-universal.dmg"
rm -f "$DMG"
hdiutil create -volname MacClean -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [ -n "${MACCLEAN_NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$MACCLEAN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
rm -rf "$STAGE"
lipo -info "$APP/Contents/MacOS/MacClean"
echo "Created: $DMG"
