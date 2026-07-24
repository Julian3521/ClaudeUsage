#!/usr/bin/env bash
#
# Build, sign, notarize and package ClaudeUsage.app into a DMG for GitHub release.
#
# One-time prerequisites (paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate in Xcode
#      (Settings → Accounts → Manage Certificates → +).
#   2. Store notarization credentials once:
#        xcrun notarytool store-credentials ClaudeUsageNotary \
#          --apple-id "you@example.com" --team-id 77UHX55UF6 \
#          --password "<app-specific-password>"   # appleid.apple.com → App-Specific Passwords
#
# Usage:
#   TEAM_ID=77UHX55UF6 ./scripts/release.sh
#
# Env overrides: TEAM_ID, DEV_ID ("Developer ID Application: …"), NOTARY_PROFILE, SKIP_NOTARIZE=1
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-77UHX55UF6}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ClaudeUsageNotary}"
DEV_ID="${DEV_ID:-Developer ID Application}"
SCHEME="ClaudeUsage"
APP_NAME="ClaudeUsage"
BUILD_DIR="$(pwd)/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP_NAME.dmg"

# A tag that doesn't match MARKETING_VERSION is the one release failure nobody
# notices: the DMG ships as the OLD version, the appcast advertises the old
# <sparkle:version>, every installed copy compares equal and is never offered the
# update — and appcast.py then drops the previous item as a duplicate.
TAG="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
if [[ -n "$TAG" ]]; then
  MARKETING="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
  if [[ "${TAG#v}" != "$MARKETING" ]]; then
    echo "✗ Tag $TAG does not match MARKETING_VERSION '$MARKETING' in project.yml." >&2
    echo "  Bump project.yml (MARKETING_VERSION and CURRENT_PROJECT_VERSION) or retag." >&2
    exit 1
  fi
  echo "▸ Releasing $TAG (marketing version $MARKETING)"
fi

command -v xcodegen >/dev/null && xcodegen generate

# The Release configuration signs manually with the Developer ID cert + a Developer
# ID provisioning profile (see project.yml). The certificate and both profiles must
# be installed: locally that's your keychain/profiles; in CI the workflow installs
# them from secrets. No App Store Connect account/key is needed.
echo "▸ Archiving (Developer ID)…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" archive

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"

# Sparkle ships its helper binaries pre-signed; under manual signing Xcode leaves
# them as-is, which notarization rejects ("not signed with a valid Developer ID /
# no secure timestamp"). Re-sign them inside-out with our cert + timestamp +
# hardened runtime, then re-seal the framework and the app.
SP="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SP" ]; then
  echo "▸ Re-signing Sparkle helpers…"
  APP_ENT="$BUILD_DIR/app.entitlements"
  codesign -d --entitlements - --xml "$APP" > "$APP_ENT" 2>/dev/null
  for comp in \
    "$SP/Versions/Current/Autoupdate" \
    "$SP/Versions/Current/Updater.app" \
    "$SP/Versions/Current/XPCServices/Downloader.xpc" \
    "$SP/Versions/Current/XPCServices/Installer.xpc"; do
    [ -e "$comp" ] && codesign -f --options runtime --timestamp -s "$DEV_ID" "$comp"
  done
  codesign -f --options runtime --timestamp -s "$DEV_ID" "$SP"
  codesign -f --options runtime --timestamp --entitlements "$APP_ENT" -s "$DEV_ID" "$APP"
fi

echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=1 "$APP"

# Notarize and staple the .app FIRST, so the copy inside the DMG carries its own
# ticket. Stapling only the DMG leaves an app that fails Gatekeeper when it's
# copied out and first launched offline.
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "▸ Notarizing app…"
  APP_ZIP="$BUILD_DIR/$APP_NAME-app.zip"
  rm -f "$APP_ZIP"
  ditto -c -k --keepParent "$APP" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$APP_ZIP"
fi

echo "▸ Building DMG…"
rm -f "$DMG"
# Stage the app next to an /Applications symlink so the DMG shows the classic
# "drag the app onto Applications" layout.
DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
  -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "▸ Notarizing DMG…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▸ Stapling DMG…"
  xcrun stapler staple "$DMG"
fi

echo "✓ Done: $DMG"
