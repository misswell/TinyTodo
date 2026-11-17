#!/usr/bin/env bash
# Ad-hoc developer DMG (no Developer ID / notarization). For distribution use
# scripts/release.sh + scripts/notarize.sh instead.
# Usage: bash scripts/make_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$ROOT/project.yml" | head -1 | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"]*)"?.*/\1/')"
VERSION="${VERSION:-1.0.0}"

BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
STAGE="$BUILD_DIR/dmg-stage"
DMG="$BUILD_DIR/TinyTodo-$VERSION.dmg"

echo "==> Building TinyTodo $VERSION (Release)"
mkdir -p "$BUILD_DIR"
rm -rf "$STAGE" "$DMG"
xcodebuild \
  -project "$ROOT/TinyTodo.xcodeproj" \
  -scheme TinyTodo \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build

APP="$DERIVED/Build/Products/Release/TinyTodo.app"
if [ ! -d "$APP" ]; then
  echo "Build product not found: $APP" >&2
  exit 1
fi

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/TinyTodo.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
  -volname "TinyTodo" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG"
ls -lh "$DMG"
