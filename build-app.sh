#!/bin/zsh
# Builds a universal "dist/FNB58 Monitor.app" and "dist/FNB58-Monitor.dmg" for Apple Silicon and Intel.
# Needs only the Xcode command line tools.
# Optional: VERSION sets the marketing version and BUILD_NUMBER sets the build number.
set -euo pipefail
cd "${0:A:h}"

swift run -c release fnbcheck Tests

APP="dist/FNB58 Monitor.app"
DMG="dist/FNB58-Monitor.dmg"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# SwiftPM records the deployment target as the SDK version. macOS would then run the app in
# compatibility mode, without Liquid Glass, so record the SDK it was really built against.
SDK_VERSION="$(xcrun --show-sdk-version)"
SLICES=()
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --product FNB58Monitor
  SLICE="$TMP/FNB58Monitor-$ARCH"
  xcrun vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace \
    -output "$SLICE" "$(swift build -c release --arch "$ARCH" --show-bin-path)/FNB58Monitor"
  SLICES+=("$SLICE")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/FNB58Monitor"

cp Packaging/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

swiftc Packaging/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Name the app in its signature's requirement so macOS can treat rebuilds as the same app and
# keep its Bluetooth permission. Ad-hoc signing would otherwise tie it to this exact binary.
codesign --force --sign - --identifier local.fnb58monitor \
  --requirements '=designated => identifier "local.fnb58monitor"' "$APP"
codesign --verify --strict "$APP"

STAGE="$TMP/dmg"
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "FNB58 Monitor" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/FNB58Monitor"))"
echo "Built $DMG"
