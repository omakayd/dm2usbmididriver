#!/bin/bash
# Builds "DM2 Settings.app" (universal arm64 + x86_64, macOS 11.0+, ad-hoc signed) into build.noindex/.
set -euo pipefail
cd "$(dirname "$0")"

OUT="build.noindex"
APP="$OUT/DM2 Settings.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$OUT/obj" "$APP"
mkdir -p "$OUT/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library -module-name DM2Settings \
        -sdk "$SDK" -target "$arch-apple-macos11.0" \
        Sources/*.swift -o "$OUT/obj/DM2Settings-$arch"
done

lipo -create "$OUT/obj/DM2Settings-arm64" "$OUT/obj/DM2Settings-x86_64" -output "$APP/Contents/MacOS/DM2 Settings"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"
