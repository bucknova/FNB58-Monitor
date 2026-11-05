#!/bin/zsh
# Builds a universal "dist/FNB58 Monitor.app", plus two DMGs:
#   dist/FNB58-Monitor-Universal.dmg     Apple Silicon and Intel
#   dist/FNB58-Monitor-AppleSilicon.dmg  Apple Silicon only, and smaller
# Needs only the Xcode command line tools.
# Optional: VERSION sets the marketing version and BUILD_NUMBER sets the build number.
set -euo pipefail
cd "${0:A:h}"

swift run -c release fnbcheck Tests

APP="dist/FNB58 Monitor.app"
rm -rf "$APP" dist/*.dmg
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
sign_app() {
  codesign --force --sign - --identifier local.fnb58monitor \
    --requirements '=designated => identifier "local.fnb58monitor"' "$1"
  codesign --verify --strict "$1"
}

make_dmg() {
  local stage="$1" dmg="$2"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "FNB58 Monitor" -srcfolder "$stage" -ov -format UDZO "$dmg"
  hdiutil verify -quiet "$dmg"
  echo "Built $dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
}

sign_app "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/FNB58Monitor"))"

STAGE="$TMP/universal"
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
make_dmg "$STAGE" dist/FNB58-Monitor-Universal.dmg

STAGE="$TMP/applesilicon"
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
THIN="$STAGE/FNB58 Monitor.app/Contents/MacOS/FNB58Monitor"
lipo "$THIN" -thin arm64 -output "$TMP/FNB58Monitor-thin"
cp "$TMP/FNB58Monitor-thin" "$THIN"
[[ "$(lipo -archs "$THIN")" == "arm64" ]]
sign_app "$STAGE/FNB58 Monitor.app"
make_dmg "$STAGE" dist/FNB58-Monitor-AppleSilicon.dmg
