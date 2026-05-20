#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$(cd "$FLUTTER_DIR/../SpringBoot" && pwd)}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
API_BASE_URL="${AVA_API_BASE_URL:-http://112.166.136.198:8080}"
WS_URL="${AVA_WS_URL:-ws://112.166.136.198:8080/ws}"

cd "$FLUTTER_DIR"

PUBSPEC_VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${1:-${PUBSPEC_VERSION%%+*}}"
BUILD_NUMBER="${2:-}"
if [[ -z "$BUILD_NUMBER" ]]; then
  if [[ "$PUBSPEC_VERSION" == *"+"* ]]; then
    BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
  else
    IFS='.' read -r major minor patch <<< "$VERSION"
    BUILD_NUMBER="$((major * 1000000 + minor * 1000 + patch))"
    if [[ "$BUILD_NUMBER" -le 0 ]]; then
      BUILD_NUMBER="1"
    fi
  fi
fi

"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build macos \
  --release \
  --no-pub \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define=AVA_API_BASE_URL="$API_BASE_URL" \
  --dart-define=AVA_WS_URL="$WS_URL"

RELEASE_DIR="$FLUTTER_DIR/build/macos/Build/Products/Release"
APP_BUNDLE="$(find "$RELEASE_DIR" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$APP_BUNDLE" ]]; then
  echo "No .app bundle was produced in $RELEASE_DIR" >&2
  exit 1
fi

UPDATES_DIR="$BACKEND_DIR/AppUpdates"
DIST_DIR="$FLUTTER_DIR/dist/macos"
mkdir -p "$UPDATES_DIR" "$DIST_DIR"

ZIP_PATH="$UPDATES_DIR/ava-macos-$VERSION.zip"
DMG_PATH="$DIST_DIR/ava-macos-$VERSION.dmg"
rm -f "$ZIP_PATH" "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
hdiutil create \
  -volname "AVA $VERSION" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "$ZIP_PATH")"

echo "Created macOS update package:"
echo "  $ZIP_PATH"
echo "  version: $VERSION"
echo "  build:   $BUILD_NUMBER"
echo "  api:     $API_BASE_URL"
echo "  ws:      $WS_URL"
echo "  sha256:  $SHA256"
echo "  bytes:   $SIZE_BYTES"
echo ""
echo "Created macOS installer image:"
echo "  $DMG_PATH"
echo ""
echo "Server config:"
echo "  AVA_APP_MACOS_LATEST_VERSION=$VERSION"
echo "  AVA_APP_MACOS_FILE_NAME=ava-macos-$VERSION.zip"
