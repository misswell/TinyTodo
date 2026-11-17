#!/usr/bin/env bash
#
# Build a Developer ID signed TinyTodo.app (hardened runtime + secure timestamp)
# and package an installable DMG. Use scripts/notarize.sh afterwards to submit
# the app and the DMG to Apple and staple the tickets.
#
# Signing identity / team default to the machine's Developer ID (U8U443D7ZL);
# override with SIGNING_IDENTITY=... TEAM_ID=...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$ROOT/project.yml" | head -1 | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"]*)"?.*/\1/')"
VERSION="${VERSION:-1.0.0}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Guofeng Liu (U8U443D7ZL)}"
TEAM="${TEAM_ID:-U8U443D7ZL}"

BUILD_DIR="$ROOT/build"
PRODUCTS="$BUILD_DIR/products"
STAGE="$BUILD_DIR/dmg-stage"
APP="$PRODUCTS/TinyTodo.app"
DMG="$BUILD_DIR/TinyTodo-$VERSION.dmg"

echo "==> 1. Release build with Developer ID"
rm -rf "$PRODUCTS" "$STAGE" "$DMG"
mkdir -p "$PRODUCTS"
xcodebuild \
  -project "$ROOT/TinyTodo.xcodeproj" \
  -scheme TinyTodo \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build \
  | tail -3

SRC="$BUILD_DIR/DerivedData/Build/Products/Release/TinyTodo.app"
[[ -d "$SRC" ]] || { echo "build product missing: $SRC" >&2; exit 1; }
cp -R "$SRC" "$APP"

echo "==> 2. Verify the signature"
codesign --verify --strict --verbose=2 "$APP"
SIGN_INFO="$(codesign -dvvv "$APP" 2>&1)"
echo "$SIGN_INFO" | grep -E "^(Authority|TeamIdentifier|Timestamp|Runtime Version|flags)=" || true
grep -q "Authority=Developer ID Application" <<<"$SIGN_INFO" || { echo "not Developer ID signed" >&2; exit 1; }
grep -q "Timestamp=" <<<"$SIGN_INFO" || { echo "signature has no secure timestamp" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$SIGN_INFO" || { echo "hardened runtime is not enabled" >&2; exit 1; }

echo "==> 3. Package DMG (unnotarized; notarize.sh rebuilds from the stapled app)"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/TinyTodo.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "TinyTodo $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
echo "  app: $APP"
echo "  dmg: $DMG"
echo "  next: bash scripts/notarize.sh"
