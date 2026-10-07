#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
APP="$ROOT_DIR/build/Pebble Click Flash.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SCRIPT_DIR/thunder.wav" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.goroman.pebble-click-flash</string>
<key>CFBundleName</key><string>Pebble Click Flash</string>
<key>CFBundleExecutable</key><string>PebbleClickFlash</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>Pebbleリングのクリック通知を受け取り、画面をフラッシュします。</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>Pebbleリングのクリック通知を受け取ります。</string>
</dict></plist>
PLIST
xcrun swiftc -O -framework AppKit -framework CoreBluetooth \
    "$SCRIPT_DIR/ClickCounter.swift" "$SCRIPT_DIR/AudioCodec.swift" \
    "$SCRIPT_DIR/AudioReceiver.swift" "$SCRIPT_DIR/SpeechPipeline.swift" \
    "$SCRIPT_DIR/AudioWaveOverlay.swift" "$SCRIPT_DIR/ThunderboltView.swift" "$SCRIPT_DIR/CommentOverlay.swift" "$SCRIPT_DIR/main.swift" \
    -o "$APP/Contents/MacOS/PebbleClickFlash"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
