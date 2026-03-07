#!/bin/bash
set -euo pipefail

APP_NAME="InstantExplain"
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

# Kill existing instance if running
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

mkdir -p "$BUNDLE_MACOS"
cp "$BINARY" "$BUNDLE_MACOS/${APP_NAME}"
cp "Resources/Info.plist" "$BUNDLE_CONTENTS/Info.plist"
mkdir -p "${BUNDLE_CONTENTS}/Resources"
cp "Resources/default-prompt.md" "${BUNDLE_CONTENTS}/Resources/default-prompt.md"

echo "==> Signing..."
codesign -s - --force "$APP_DIR"

echo "==> Resetting Accessibility permission (ad-hoc signing invalidates previous grant)..."
BUNDLE_ID=$(defaults read "$BUNDLE_CONTENTS/Info.plist" CFBundleIdentifier 2>/dev/null || echo "com.chaukam.instant-explain")
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "==> Ensuring config directory exists..."
CONFIG_DIR="$HOME/.config/instant-explain"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ] || ! grep -q '"sk-ant-' "$CONFIG_FILE"; then
    echo ""
    echo "  No API key found. Enter your Anthropic API key (sk-ant-...):"
    read -r -p "  > " API_KEY
    if [ -n "$API_KEY" ]; then
        echo "{\"api_key\": \"$API_KEY\"}" > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo "  API key saved to ${CONFIG_FILE}"
    else
        echo '{"api_key": ""}' > "$CONFIG_FILE"
        echo "  Created ${CONFIG_FILE} — add your Anthropic API key there."
    fi
fi

# Install default prompt template if missing
PROMPT_FILE="${CONFIG_DIR}/prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
    cp "Resources/default-prompt.md" "$PROMPT_FILE"
    echo "  Installed default prompt template to ${PROMPT_FILE}"
fi

echo "==> Launching ${APP_NAME}..."
open "$APP_DIR"

echo ""
echo "Done! ${APP_NAME} is running in your menu bar."
echo "  - Press F5 with text selected to get an explanation"
echo "  - Grant Accessibility access if prompted"
echo "  - Config: ${CONFIG_FILE}"
echo "  - Prompt: ${PROMPT_FILE}"
