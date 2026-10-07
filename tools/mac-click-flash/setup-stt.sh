#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
MODEL_PATH="$ROOT_DIR/build/models/ggml-small.bin"
MODEL_SHA=1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b
for tool in ffmpeg whisper-cli; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing %s. Install with: brew install ffmpeg whisper-cpp\n' "$tool" >&2
        exit 1
    fi
done
mkdir -p "$ROOT_DIR/build/models"
if [ -f "$MODEL_PATH" ] && printf '%s  %s\n' "$MODEL_SHA" "$MODEL_PATH" | shasum -a 256 -c - >/dev/null 2>&1; then
    printf 'Model verified: %s\n' "$MODEL_PATH"
    exit 0
fi
curl --fail --location --retry 3 \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin \
    --output "$MODEL_PATH.partial"
printf '%s  %s\n' "$MODEL_SHA" "$MODEL_PATH.partial" | shasum -a 256 -c -
mv "$MODEL_PATH.partial" "$MODEL_PATH"
printf 'Model ready: %s\n' "$MODEL_PATH"
