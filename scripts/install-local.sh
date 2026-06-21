#!/usr/bin/env bash
#
# Install the latest Xcode-built (signed) app into /Applications and force the
# widget system to reload it. Run AFTER building in Xcode (⌘R), because only the
# Xcode build is signed with your team — the widget won't register otherwise.
#
#   ./scripts/install-local.sh
set -euo pipefail

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/ClaudeUsage-*/Build/Products/Debug/ClaudeUsage.app 2>/dev/null | head -1)
[ -z "${APP:-}" ] && { echo "No build found — run the ClaudeUsage scheme in Xcode (⌘R) first."; exit 1; }

echo "▸ Installing $APP"
osascript -e 'quit app "ClaudeUsage"' 2>/dev/null || true
rm -rf /Applications/ClaudeUsage.app
cp -R "$APP" /Applications/

echo "▸ Refreshing widget registration"
pluginkit -a /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidgetExtension.appex 2>/dev/null || true
killall chronod 2>/dev/null || true   # widget daemon — relaunches automatically

open /Applications/ClaudeUsage.app
echo "✓ Done. If a placed widget still looks old, remove it and add it again."
pluginkit -mAv | grep -i claude || true
