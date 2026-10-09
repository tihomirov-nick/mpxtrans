#!/bin/bash
# Builds build/Slovo.app (universal: Apple Silicon + Intel).
#   VERSION=1.1.0 ./scripts/build_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# A Command Line Tools SDK set in the environment may not match the Xcode compiler.
unset SDKROOT

APP_NAME="Slovo"
BUNDLE_ID="${BUNDLE_ID:-com.slovo.app}"
VERSION="${VERSION:-1.2.3}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP="$ROOT/build/$APP_NAME.app"
VAD_MODEL="ggml-silero-v6.2.0.bin"
COPYRIGHT_EN="© 2026 Nick. Speech recognition: whisper.cpp (MIT), audio: FFmpeg"
COPYRIGHT_RU="© 2026 Nick. Распознавание речи: whisper.cpp (MIT), звук: FFmpeg"
# Signature: SIGN_IDENTITY from the environment ("-" is ad-hoc), else the author's own certificate "tihomirov-nick"
# when it is in the Keychain, else ad-hoc. Installed copies take only updates signed with that certificate. It is
# self-signed, so find-identity calls it not trusted: that is expected, and only its name is looked for.
OWN_IDENTITY="tihomirov-nick"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q "\"$OWN_IDENTITY\""; then
        SIGN_IDENTITY="$OWN_IDENTITY"
    else
        SIGN_IDENTITY="-"
    fi
fi

# 1. Dependencies
[ -f Vendor/whisper/lib/libwhisper_all.a ] || ./scripts/build_whisper.sh
[ -x Vendor/ffmpeg/ffmpeg ] || ./scripts/fetch_ffmpeg.sh
[ -f "Resources/$VAD_MODEL" ] || ./scripts/fetch_vad.sh

# 2. Compile (universal binary)
echo "==> swift build (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME" 2>&1 | grep -E "error|warning: unre|Build complete" || true
BIN="$ROOT/.build/out/Products/Release/$APP_NAME"
[ -x "$BIN" ] || BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }

# 3. Bundle
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" \
         "$APP/Contents/Resources/ru.lproj" "$APP/Contents/Resources/en.lproj"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
strip -x "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
cp Vendor/ffmpeg/ffmpeg "$APP/Contents/Helpers/ffmpeg"
cp "Resources/$VAD_MODEL" "$APP/Contents/Resources/"

# Icon: Resources/AppIcon.icon in the Icon Composer format, made by scripts/make_icon.swift (flat: a solid fill and the
# white mark, no glass, shadow or translucency). actool turns it into Assets.car, which macOS 26 shows without the grey
# plate it puts around plain .icns icons, and AppIcon.icns for older systems.
[ -d Resources/AppIcon.icon ] || swift scripts/make_icon.swift
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.3 --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/icon-partial.plist" --output-format human-readable-text >/dev/null
[ -f "$APP/Contents/Resources/Assets.car" ] && [ -f "$APP/Contents/Resources/AppIcon.icns" ] || { echo "icon compilation failed"; exit 1; }

# Interface languages: Russian strings are the keys in the code, English comes from Localizable.strings
# (scripts/l10n/make_strings.py builds it from scripts/l10n/en.json and stops if a translation is missing).
python3 scripts/l10n/make_strings.py >/dev/null
cp Resources/en.lproj/Localizable.strings "$APP/Contents/Resources/en.lproj/"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleDisplayName = "$APP_NAME";
CFBundleName = "$APP_NAME";
NSHumanReadableCopyright = "$COPYRIGHT_EN";
"Audio" = "Audio";
"Video" = "Video";
"Media (other formats)" = "Media (other formats)";
STRINGS
cat > "$APP/Contents/Resources/ru.lproj/InfoPlist.strings" <<STRINGS
CFBundleDisplayName = "$APP_NAME";
CFBundleName = "$APP_NAME";
NSHumanReadableCopyright = "$COPYRIGHT_RU";
"Audio" = "Аудио";
"Video" = "Видео";
"Media (other formats)" = "Аудио и видео (другие форматы)";
STRINGS

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.3</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>$COPYRIGHT_EN</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Audio</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.audio</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Video</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.video</string>
                <string>public.audiovisual-content</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Media (other formats)</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mkv</string><string>webm</string><string>avi</string><string>flv</string><string>wmv</string>
                <string>ts</string><string>mts</string><string>m2ts</string><string>3gp</string><string>ogv</string>
                <string>vob</string><string>mxf</string><string>mpg</string><string>mpeg</string><string>m4v</string>
                <string>ogg</string><string>oga</string><string>opus</string><string>flac</string><string>amr</string>
                <string>wma</string><string>ape</string><string>wv</string><string>mka</string><string>caf</string>
                <string>dts</string><string>ac3</string><string>m4b</string><string>aif</string><string>aiff</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
printf "APPL????" > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# 4. Sign (inner code first)
echo "==> codesign ($SIGN_IDENTITY)"
xattr -cr "$APP"
case "$SIGN_IDENTITY" in
    "Developer ID Application:"*)
        # For notarization: hardened runtime and a secure timestamp.
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/ffmpeg"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
        ;;
    *)
        codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/ffmpeg"
        codesign --force --sign "$SIGN_IDENTITY" "$APP"
        ;;
esac
codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /    designated requirement: /p'
echo "==> done: $APP ($(du -sh "$APP" | cut -f1))"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
