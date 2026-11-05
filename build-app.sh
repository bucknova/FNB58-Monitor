#!/bin/zsh
# Builds "dist/FNB58 Monitor.app". Needs only the Xcode command line tools.
set -euo pipefail
cd "${0:A:h}"
swift run -c release fnbcheck Tests
swift build -c release --product FNB58Monitor
APP="dist/FNB58 Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/FNB58Monitor" "$APP/Contents/MacOS/FNB58Monitor"
# SwiftPM records the deployment target as the SDK version. macOS would then run the app in
# compatibility mode, without Liquid Glass, so record the SDK it was really built against.
SDK_VERSION="$(xcrun --show-sdk-version)"
xcrun vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/FNB58Monitor" "$APP/Contents/MacOS/FNB58Monitor"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
TMP="$(mktemp -d)"
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
rm -rf "$TMP"
# Name the app in its signature's requirement so macOS can treat rebuilds as the same app and
# keep its Bluetooth permission. Ad-hoc signing would otherwise tie it to this exact binary.
codesign --force --sign - --identifier local.fnb58monitor \
  --requirements '=designated => identifier "local.fnb58monitor"' "$APP"
echo "Built $APP"
