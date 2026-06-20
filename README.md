# Claude Usage — macOS Menu Bar + Widget

A tiny macOS **menu-bar app** and **WidgetKit widget** that show your **Claude
session (5h) and weekly (7d) usage limits** — the same numbers you see under
`claude /usage` and in the Claude app's *Usage* screen.

The menu bar shows the live session percentage; clicking it opens a panel with
bars + reset countdowns. A desktop / Notification Center widget shows the same.

It signs in to **your own** Claude account and reads the limits directly from
Anthropic's usage endpoint. No data leaves your Mac except the calls to
Anthropic. The OAuth token is stored in the Keychain and shared with the widget.

> ⚠️ **Unofficial.** This reuses the public Claude Code OAuth client and an
> undocumented usage endpoint (`/api/oauth/usage`). It is meant for personal use
> with your own account. Anthropic may change or block it at any time, in which
> case the app will need updating. Not affiliated with Anthropic.

## Requirements

- **macOS 14 (Sonoma) or newer** and **Xcode 16+** (developed with Xcode 26).
- A **paid Apple Developer account** (for App Sandbox + Keychain sharing between
  the app and the widget). The Team ID is set in [`project.yml`](project.yml)
  (`DEVELOPMENT_TEAM`) — change it to your own.
- A Claude subscription (Pro/Max).

## Build & run

```bash
# (Optional) regenerate the Xcode project from project.yml
brew install xcodegen
xcodegen generate

open ClaudeUsage.xcodeproj
```

In Xcode:

1. Signing is preconfigured via `DEVELOPMENT_TEAM`. If you use a different
   account, select your **Team** on both the **ClaudeUsage** and
   **ClaudeUsageWidgetExtension** targets under *Signing & Capabilities*. On the
   first run Xcode mints the provisioning profiles automatically.
2. Run the **ClaudeUsage** scheme. The app is a menu-bar agent (no Dock icon) —
   look for the gauge icon in the menu bar.
3. Click it → **"Bei Claude anmelden"** and log in. The code is captured
   automatically. (If the embedded web view fails — e.g. Google SSO — use
   **"Manuell…"**: open the page in your browser and paste the shown code.)
4. Add the widget: right-click the desktop → *Edit Widgets* (or open Notification
   Center → *Edit Widgets*) → search **Claude Usage** → pick Small / Medium / Large.

## How it works

```text
App  ──login──▶ platform.claude.com/oauth/authorize  (PKCE)
     ──code───▶ platform.claude.com/v1/oauth/token    → access + refresh token (Keychain)
App & Widget ─▶ api.anthropic.com/api/oauth/usage     (Bearer + anthropic-beta header)
                 → five_hour / seven_day / seven_day_opus  → rings & bars
```

- **`Shared/`** — models, OAuth (PKCE), Keychain token + snapshot store, usage
  API, shared SwiftUI ring/bar views. Compiled into both targets.
- **`App/`** — `MenuBarExtra` app + login window (`WKWebView`). A periodic timer
  refreshes the menu-bar value; an `AppDelegate` drives it on launch.
- **`Widget/`** — WidgetKit timeline provider + Small/Medium/Large views.
  Refreshes ~every 20 min (WidgetKit budgets refreshes; not real-time).

The app and widget share both the OAuth token and the last usage snapshot through
a single shared **Keychain access group** (no App Group needed).

## If the percentages look wrong

The exact JSON shape of `/api/oauth/usage` is undocumented, so the decoder in
[`Shared/UsageModels.swift`](Shared/UsageModels.swift) is deliberately tolerant.
From the menu, use **⋯ → "Rohdaten kopieren"** to copy the real response, then
adjust the `CodingKeys` / `UsageWindow` decoding to match (e.g. if `utilization`
is named differently or is a 0–1 fraction vs a 0–100 percent).

## Making it yours

Bundle IDs and the shared Keychain group are hardcoded to `com.jb.*` in
[`project.yml`](project.yml) and the two `.entitlements` files (the app and
widget share data purely through the Keychain — no App Group). Change them
consistently if you want your own identifiers, then re-run `xcodegen generate`.

## License

Personal project. Use at your own risk.
