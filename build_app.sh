#!/bin/bash
# Builds the HebrewLayoutFixer Swift package and packages it into a double-clickable
# macOS .app bundle (HebrewLayoutFixer.app) in the project root.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HebrewLayoutFixer"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building release binaries for arm64 and x86_64…"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM64_BIN=".build/arm64-apple-macosx/release/${APP_NAME}"
X86_64_BIN=".build/x86_64-apple-macosx/release/${APP_NAME}"
if [ ! -f "$ARM64_BIN" ] || [ ! -f "$X86_64_BIN" ]; then
    echo "Build failed: one of the per-arch binaries is missing" >&2
    exit 1
fi

echo "==> Combining into a universal binary…"
UNIVERSAL_BIN="$(mktemp -t ${APP_NAME})"
lipo -create -output "$UNIVERSAL_BIN" "$ARM64_BIN" "$X86_64_BIN"
BIN_PATH="$UNIVERSAL_BIN"

echo "==> Assembling ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $(pwd)/${APP_BUNDLE}"
echo "העתק/י אותו לתיקיית Applications והרץ/י. בהפעלה ראשונה תתבקש/י לאשר הרשאת נגישות."
