#!/bin/bash
# Still build script.
#   ./build.sh                                  handoff build (isolated bundle id, ad-hoc signed)
#   SIGN_IDENTITY="Developer ID Application: …" BUNDLE_ID=com.still.focus ./build.sh
#                                               release build (hardened runtime, mic entitlement)
set -euo pipefail
cd "$(dirname "$0")"
app=build/Still.app
bundle_id="${BUNDLE_ID:-com.still.focus.handoff}"
identity="${SIGN_IDENTITY:--}"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
cp Resources/Info.plist "$app/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
cp Resources/Still.icns "$app/Contents/Resources/"

swiftc Sources/*.swift -module-cache-path build/module-cache -o "$app/Contents/MacOS/Still" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework Carbon \
  -framework Security -framework LocalAuthentication -framework AuthenticationServices \
  -target arm64-apple-macosx14.0 -O -wmo

if [ "$identity" = "-" ]; then
  codesign --force --deep --sign - "$app"
else
  codesign --force --deep --options runtime --timestamp \
    --entitlements Resources/Still.entitlements --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"
echo "Built $app ($bundle_id, signed: ${identity/#-/ad-hoc})"
