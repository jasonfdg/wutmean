#!/bin/bash
set -euo pipefail

APP_NAME="wutmean"
APP_DIR="/Applications/${APP_NAME}.app"
BUNDLE_CONTENTS="${APP_DIR}/Contents"
BUNDLE_MACOS="${BUNDLE_CONTENTS}/MacOS"

echo "==> Building ${APP_NAME}..."
swift build -c release 2>&1

BINARY=".build/release/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed — binary not found at ${BINARY}"
    exit 1
fi

echo "==> Creating app bundle at ${APP_DIR}..."

# Kill existing instance if running (check both old and new names)
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "InstantExplain" 2>/dev/null || true
sleep 0.5

mkdir -p "$BUNDLE_MACOS"
cp "$BINARY" "$BUNDLE_MACOS/${APP_NAME}"
cp "Resources/Info.plist" "$BUNDLE_CONTENTS/Info.plist"
mkdir -p "${BUNDLE_CONTENTS}/Resources"
cp "Resources/default-prompt.md" "${BUNDLE_CONTENTS}/Resources/default-prompt.md"
cp "Resources/AppIcon.icns" "${BUNDLE_CONTENTS}/Resources/AppIcon.icns"

echo "==> Signing..."
codesign -s - --force "$APP_DIR"

echo "==> Resetting Accessibility permission (re-signing invalidates old TCC entry)..."
tccutil reset Accessibility com.chaukam.wutmean 2>/dev/null || true

echo "==> Ensuring config directory exists..."
CONFIG_DIR="$HOME/.config/wutmean"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

# Migrate from old instant-explain config if it exists
OLD_CONFIG_DIR="$HOME/.config/instant-explain"
if [ -d "$OLD_CONFIG_DIR" ] && [ ! -f "$CONFIG_FILE" ]; then
    echo "  Migrating config from instant-explain..."
    cp -n "$OLD_CONFIG_DIR"/* "$CONFIG_DIR"/ 2>/dev/null || true
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"api_key": ""}' > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi


# Clean up old app bundle
OLD_APP="/Applications/InstantExplain.app"
if [ -d "$OLD_APP" ]; then
    echo "==> Removing old InstantExplain.app..."
    rm -rf "$OLD_APP"
fi

echo "==> Launching ${APP_NAME}..."
open "$APP_DIR"

echo ""
echo "Done! ${APP_NAME} is running in your menu bar."
echo "  - On first launch, you'll be prompted to enter your API key"
echo "  - Double-tap F1 with text selected to get an explanation"
echo "  - Grant Accessibility access if prompted"
echo "  - Config: ${CONFIG_FILE}"
echo "  - Prompt is bundled inside the app"
