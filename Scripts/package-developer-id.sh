#!/bin/bash
# Build, sign, notarize, and staple a direct-distribution copy of Ice.
# SIGNING_IDENTITY is a Developer ID Application certificate name or SHA-1 hash.
# NOTARY_PROFILE is an existing notarytool keychain profile.
# The finished app and ZIP are written to build/developer-id by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application certificate}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
OUTPUT_DIR="$ROOT/build/developer-id"
DERIVED="${DERIVED:-$ROOT/build/derived-data}"
mkdir -p "$OUTPUT_DIR"
STAGING="$(mktemp -d /tmp/ice-developer-id.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO build -quiet > "$OUTPUT_DIR/build.log" 2>&1 || {
        tail -50 "$OUTPUT_DIR/build.log" >&2
        exit 1
    }

SOURCE_APP="$DERIVED/Build/Products/Release/Ice.app"
APP="$STAGING/Ice.app"
test -d "$SOURCE_APP"
ditto "$SOURCE_APP" "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() {
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$1"
}

sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/XPCServices/MenuBarItemService.xpc"
codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Scripts/DeveloperID.entitlements" \
    --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$STAGING/Ice.zip"
xcrun notarytool submit "$STAGING/Ice.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

rm -rf "$OUTPUT_DIR/Ice.app"
ditto "$APP" "$OUTPUT_DIR/Ice.app"
ditto -c -k --keepParent "$APP" "$OUTPUT_DIR/Ice.zip"
codesign --verify --deep --strict "$OUTPUT_DIR/Ice.app"
xcrun stapler validate "$OUTPUT_DIR/Ice.app"
spctl --assess --type execute "$OUTPUT_DIR/Ice.app"
unzip -tq "$OUTPUT_DIR/Ice.zip"
mkdir "$STAGING/extracted"
ditto -x -k "$OUTPUT_DIR/Ice.zip" "$STAGING/extracted"
codesign --verify --deep --strict "$STAGING/extracted/Ice.app"
xcrun stapler validate "$STAGING/extracted/Ice.app"
spctl --assess --type execute "$STAGING/extracted/Ice.app"
echo "Notarized app: $OUTPUT_DIR/Ice.app"
echo "Notarized ZIP: $OUTPUT_DIR/Ice.zip"
echo "Install Ice.app at /Applications/Ice.app on macOS 27."
