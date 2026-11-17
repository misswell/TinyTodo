#!/usr/bin/env bash
#
# Submit a Developer ID signed TinyTodo.app to Apple's notary service, staple the
# app, rebuild the DMG from the stapled app, notarize and staple that too.
#
# Credentials: a notarytool keychain profile (default: agentspace-notary, this
# machine's live profile) or asc API-key credentials. A profile *name* proves
# nothing — the credential is verified live before any submission.
#
#   bash scripts/notarize.sh
#   NOTARY_PROFILE=other bash scripts/notarize.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$ROOT/project.yml" | head -1 | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"]*)"?.*/\1/')"
VERSION="${VERSION:-1.0.0}"
PROFILE="${NOTARY_PROFILE:-agentspace-notary}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Guofeng Liu (U8U443D7ZL)}"

APP="$ROOT/build/products/TinyTodo.app"
DMG="$ROOT/build/TinyTodo-$VERSION.dmg"
ZIP="$ROOT/build/TinyTodo-app-notarize.zip"

[[ -d "$APP" ]] || { echo "missing $APP — run scripts/release.sh first" >&2; exit 1; }

echo "== 0. Verify the notarization credential live"
MODE=""
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "   ok  notarytool profile '$PROFILE' is live"
  MODE="notarytool"
elif asc notarization list --limit 1 >/dev/null 2>&1; then
  echo "   ok  asc API-key credentials are live"
  MODE="asc"
else
  echo "no working notarization credential." >&2
  echo "restore the profile with:" >&2
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id <apple-id> --team-id U8U443D7ZL" >&2
  exit 1
fi

await_notarization() { # <file>
  local file="$1" id status out attempt
  if [[ "$MODE" == "notarytool" ]]; then
    if ! out=$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" 2>&1); then
      printf '%s\n' "$out" >&2
      echo "submission of $file failed" >&2
      return 1
    fi
    printf '%s\n' "$out" >&2
    id=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*id:[[:space:]]*//p' | head -1)
    [[ -n "$id" ]] || { echo "submission produced no id" >&2; return 1; }
    attempt=0
    while :; do
      if out=$(xcrun notarytool info "$id" --keychain-profile "$PROFILE" 2>&1); then
        status=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1)
        attempt=0
        case "$status" in
          Accepted) return 0 ;;
          Rejected|Invalid)
            echo "   submission $id came back $status" >&2
            printf '%s\n' "$out" >&2
            echo "   log: xcrun notarytool log $id --keychain-profile $PROFILE" >&2
            return 1 ;;
          "")
            ;;
          *)
            echo "   submission $id: $status; polling every 30s"
            sleep 30
            continue ;;
        esac
      fi
      attempt=$((attempt + 1))
      echo "   poll $attempt could not read status for $id:" >&2
      printf '%s\n' "${out:-<no output>}" | sed 's/^/     /' >&2
      if ((attempt >= 10)); then
        echo "   giving up; the bytes are at Apple. Re-check: xcrun notarytool info $id --keychain-profile $PROFILE" >&2
        return 1
      fi
      sleep 30
    done
  else
    asc notarization submit --file "$file" --wait
  fi
}

echo "== 1. Notarize the app and staple it"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
await_notarization "$ZIP" || { echo "app submission not accepted" >&2; exit 1; }
rm -f "$ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 2. Rebuild the DMG from the stapled app"
rm -f "$DMG"
STAGE="$ROOT/build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/TinyTodo.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "TinyTodo $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "== 2b. Sign the DMG with Developer ID (Gatekeeper checks disk images too)"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --strict "$DMG"

echo "== 3. Notarize the DMG and staple it"
await_notarization "$DMG" || { echo "DMG submission not accepted" >&2; exit 1; }
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "== 4. Verify what a user will actually get"
codesign --verify --strict "$APP" && echo "   ok  app signature verifies"
stapler validate "$APP" >/dev/null && echo "   ok  app ticket stapled"
stapler validate "$DMG" >/dev/null && echo "   ok  dmg ticket stapled"
spctl --assess --type execute "$APP" || { echo "   Gatekeeper refused the app" >&2; exit 1; }
echo "   ok  Gatekeeper accepts the app"
spctl --assess --type open --context context:primary-signature "$DMG" || { echo "   Gatekeeper refused the DMG" >&2; exit 1; }
echo "   ok  Gatekeeper accepts the DMG"

echo "==> Done: $APP and $DMG are notarized, stapled, and Gatekeeper-clean"
