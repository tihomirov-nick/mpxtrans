#!/bin/bash
# Checks that the app in a DMG is signed with the app's own certificate "tihomirov-nick": installed copies replace
# themselves only with an app whose signature satisfies their designated requirement (identifier com.slovo.app and
# this certificate's leaf hash). With a version, the app must be that version too.
#   ./scripts/verify_dmg.sh dist/Slovo-1.2.0.dmg [1.2.0]
set -euo pipefail

DMG="${1:?usage: ./scripts/verify_dmg.sh <dmg> [version]}"
VERSION="${2:-}"
APP_NAME="Slovo"
BUNDLE_ID="com.slovo.app"
LEAF="af82036140843a7d76497ea8e4cd23403c8aedc2"   # SHA-1 of the certificate "tihomirov-nick"

MOUNT="$(mktemp -d -t slovo-verify)"
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet; rmdir "$MOUNT" 2>/dev/null || true' EXIT

APP="$MOUNT/$APP_NAME.app"
[ -d "$APP" ] || { echo "no $APP_NAME.app in $DMG"; exit 1; }
if ! codesign --verify --deep --strict --test-requirement="=identifier \"$BUNDLE_ID\" and certificate leaf = H\"$LEAF\"" "$APP" 2>/dev/null; then
    echo "$APP_NAME.app in $(basename "$DMG") is not signed with \"tihomirov-nick\" as $BUNDLE_ID (its requirement:"
    echo "  $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => //p'))"
    echo "Installed copies would not update to it. Put the certificate into the Keychain (README) and build again."
    exit 1
fi
if [ -n "$VERSION" ] && [ "$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)" != "$VERSION" ]; then
    echo "$APP_NAME.app in $(basename "$DMG") is not version $VERSION"
    exit 1
fi
echo "==> $APP_NAME.app in $(basename "$DMG") is signed with \"tihomirov-nick\" ($BUNDLE_ID)"
