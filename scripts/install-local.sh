#!/usr/bin/env bash
#
# Install the latest Xcode-built (signed) app into /Applications and force the
# widget system to use it. Run AFTER building in Xcode (⌘R) — only the Xcode
# build is signed with your team; ad-hoc/CLI builds won't register a widget.
#
#   ./scripts/install-local.sh
set -euo pipefail

APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/ClaudeUsage-*/Build/Products/Debug/ClaudeUsage.app 2>/dev/null | head -1)
[ -z "${APP:-}" ] && { echo "No build found — run the ClaudeUsage scheme in Xcode (⌘R) first."; exit 1; }

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ -z "$TEAM" ] || [ "$TEAM" = "not set" ]; then
  echo "⚠️  This build is ad-hoc signed (no team) — macOS won't register its widget."
  echo "    Build the ClaudeUsage scheme in Xcode (⌘R), then re-run this script."
  exit 1
fi

echo "▸ Unregistering any stale DerivedData widget extensions"
for ax in ~/Library/Developer/Xcode/DerivedData/ClaudeUsage-*/Build/Products/*/ClaudeUsage.app/Contents/PlugIns/*.appex; do
  [ -e "$ax" ] && pluginkit -r "$ax" 2>/dev/null || true
done

echo "▸ Installing $APP (team $TEAM)"
osascript -e 'quit app "ClaudeUsage"' 2>/dev/null || true
rm -rf /Applications/ClaudeUsage.app
cp -R "$APP" /Applications/

echo "▸ Registering + reloading the widget"
pluginkit -a /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidgetExtension.appex 2>/dev/null || true
killall chronod 2>/dev/null || true

open /Applications/ClaudeUsage.app
echo "✓ Installed build $(defaults read /Applications/ClaudeUsage.app/Contents/Info.plist CFBundleVersion 2>/dev/null). Remove + re-add the widget if it still looks old."
pluginkit -mAv | grep -i claude || true
