#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 2.0.0
# Creates a signed .app bundle, zips it, and creates a GitHub release.

VERSION="${1:?Usage: $0 <version>}"
APP_NAME="wutmean"
BUILD_DIR=".build/release-stage"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BUNDLE="${APP_DIR}/Contents"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"

echo "==> Building ${APP_NAME} v${VERSION}..."

# Build for arm64 and x86_64 separately, then lipo
swift build -c release --arch arm64 2>&1
swift build -c release --arch x86_64 2>&1

rm -rf "$BUILD_DIR"
mkdir -p "${BUNDLE}/MacOS" "${BUNDLE}/Resources"

lipo -create \
    .build/arm64-apple-macosx/release/${APP_NAME} \
    .build/x86_64-apple-macosx/release/${APP_NAME} \
    -output "${BUNDLE}/MacOS/${APP_NAME}"

echo "  Universal binary created (arm64 + x86_64)"

# Copy resources
cp Resources/Info.plist "${BUNDLE}/Info.plist"
cp Resources/default-prompt.md "${BUNDLE}/Resources/default-prompt.md"
cp Resources/AppIcon.icns "${BUNDLE}/Resources/AppIcon.icns"

# Update version in plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${BUNDLE}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${BUNDLE}/Info.plist"

# Sign
codesign -s - --force --deep "$APP_DIR"
echo "==> Signed"

# Zip
cd "$BUILD_DIR"
zip -r -y "$ZIP_NAME" "${APP_NAME}.app"
cd - > /dev/null

ZIP_FULL_PATH="$(pwd)/${ZIP_PATH}"
SHA256=$(shasum -a 256 "$ZIP_FULL_PATH" | awk '{print $1}')

echo ""
echo "==> Built: ${ZIP_FULL_PATH}"
echo "==> SHA256: ${SHA256}"
echo ""

# Create GitHub release if gh is available
if command -v gh &> /dev/null; then
    read -p "Create GitHub release v${VERSION}? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gh release create "v${VERSION}" "$ZIP_FULL_PATH" \
            --title "v${VERSION}" \
            --notes "$(cat <<EOF
## wutmean v${VERSION}

### Install
\`\`\`
brew install --cask wutmean
\`\`\`
Or download \`${ZIP_NAME}\`, unzip to \`/Applications\`, and open.

**SHA256:** \`${SHA256}\`

**Requires:** macOS 13+, Accessibility permission
EOF
)"
        echo "==> Release created: https://github.com/jasonfdg/wutmean/releases/tag/v${VERSION}"
    fi
else
    echo "gh CLI not found — create the release manually at:"
    echo "  https://github.com/jasonfdg/wutmean/releases/new?tag=v${VERSION}"
fi

echo ""
echo "==> Homebrew cask SHA256: ${SHA256}"
echo "    Update the sha256 in the cask formula before submitting."
