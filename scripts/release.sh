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
SCHEME="ClaudeUsage"
APP_NAME="ClaudeUsage"
BUILD_DIR="$(pwd)/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP_NAME.dmg"

command -v xcodegen >/dev/null && xcodegen generate

# The sandbox + keychain-sharing entitlements need a provisioning profile, so use
# automatic signing with -allowProvisioningUpdates. Locally this uses your signed-in
# Xcode account; in CI set ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH (App Store
# Connect API key) and it's used to generate the Developer ID profiles.
AUTH=(-allowProvisioningUpdates)
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH+=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")
fi

echo "▸ Archiving…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
  "${AUTH[@]}" archive

echo "▸ Exporting (Developer ID)…"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" "${AUTH[@]}"

echo "▸ Building DMG…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
  -ov -format UDZO "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "▸ Notarizing…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▸ Stapling…"
  xcrun stapler staple "$DMG"
fi

echo "✓ Done: $DMG"
