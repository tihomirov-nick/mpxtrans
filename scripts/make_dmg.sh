#!/bin/bash
# Builds the app and packs it into dist/Slovo-<version>.dmg
#   VERSION=1.1.0 ./scripts/make_dmg.sh
# Signed with the author's certificate "tihomirov-nick" (SIGN_IDENTITY overrides it): installed copies update
# themselves only to versions signed with it. Without the certificate the DMG is signed ad-hoc, with a warning.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-1.2.2}"
export VERSION

OWN_IDENTITY="tihomirov-nick"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q "\"$OWN_IDENTITY\""; then
        SIGN_IDENTITY="$OWN_IDENTITY"
    else
        SIGN_IDENTITY="-"
    fi
fi
export SIGN_IDENTITY
warn_adhoc() {
    [ "$SIGN_IDENTITY" = "-" ] || return 0
    echo "" >&2
    echo "!!! WARNING: the certificate \"$OWN_IDENTITY\" is not in the Keychain, so Slovo is signed ad-hoc." >&2
    echo "!!! Copies installed from this DMG will NOT be able to update themselves. Do not publish it." >&2
    echo "" >&2
}
warn_adhoc

./scripts/build_app.sh

STAGE="$ROOT/build/dmg"
DMG="$ROOT/dist/Slovo-$VERSION.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
cp -R "$ROOT/build/Slovo.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/Как установить.txt" "$ROOT/docs/How to install.txt" "$STAGE/"

rm -f "$DMG"
echo "==> creating $DMG"
hdiutil create -volname "Slovo $VERSION" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" >/dev/null
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG" >/dev/null && echo "==> verified"
echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
warn_adhoc
