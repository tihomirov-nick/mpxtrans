#!/bin/bash
# Downloads the Silero VAD model for whisper.cpp (skips silence and music) and checks its SHA-256.
# Result: Resources/ggml-silero-v6.2.0.bin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="ggml-silero-v6.2.0.bin"
SHA256="2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"
OUT="$ROOT/Resources/$NAME"
TMP="$OUT.download"

curl -sSL --fail -o "$TMP" "https://huggingface.co/ggml-org/whisper-vad/resolve/main/$NAME"
actual=$(shasum -a 256 "$TMP" | awk '{print $1}')
if [ "$actual" != "$SHA256" ]; then
    rm -f "$TMP"
    echo "SHA256 mismatch for $NAME"
    exit 1
fi
mv "$TMP" "$OUT"
echo "$NAME downloaded OK"
