# Claude Usage — iOS Widget

A tiny iOS app + home/lock-screen widget that shows your **Claude session (5h) and
weekly (7d) usage limits** — the same numbers you see under `claude /usage` and in
the Claude app's *Usage* screen.

<img src="docs/screenshot.png" width="280" alt="Usage screen" />

It signs in to **your own** Claude account and reads the limits directly from
Anthropic's usage endpoint. No data leaves your device except the calls to
Anthropic. The OAuth token is stored in the iOS Keychain and shared with the
widget extension.

> ⚠️ **Unofficial.** This reuses the public Claude Code OAuth client and an
> undocumented usage endpoint (`/api/oauth/usage`). It is meant for personal use
> with your own account. Anthropic may change or block it at any time, in which
> case the app will need updating. Not affiliated with Anthropic.

## Requirements

- **Xcode 16 or newer** (developed with Xcode 26).
- A **paid Apple Developer account** (needed for App Groups + Keychain sharing
  between the app and the widget, and so the app runs for a year on your phone).
- An **iPhone on iOS 17+** and a Claude subscription (Pro/Max).

## Build & run

```bash
# 1. (Optional) regenerate the Xcode project from project.yml
brew install xcodegen
xcodegen generate

# 2. Open it
open ClaudeUsage.xcodeproj
```

In Xcode:

1. Select the **ClaudeUsage** target → *Signing & Capabilities* → choose your
   **Team**. Do the same for the **ClaudeUsageWidgetExtension** target.
2. Pick your iPhone as the run destination and press **▶︎ Run**.
3. In the app, tap **"Bei Claude anmelden"** and log in with your Claude account.
   The app captures the authorization code automatically. (If login fails in the
   embedded web view — e.g. Google SSO — use the **"Manuell"** button: open the
   page in Safari, log in, and paste the shown code.)
4. Long-press your home screen → **+** → search **Claude Usage** → add the widget.
   Lock-screen widgets are available too (circular + rectangular).

## How it works

```
App  ──login──▶ platform.claude.com/oauth/authorize  (PKCE)
     ──code───▶ platform.claude.com/v1/oauth/token    → access + refresh token (Keychain)
App & Widget ─▶ api.anthropic.com/api/oauth/usage     (Bearer + anthropic-beta header)
                 → five_hour / seven_day / seven_day_opus  → rings & bars
```

- **`Shared/`** — models, OAuth (PKCE), Keychain token store, usage API. Compiled
  into both targets.
- **`App/`** — SwiftUI app: login + status screen + raw-response debug view.
- **`Widget/`** — WidgetKit timeline provider + views. Refreshes ~every 20 min
  (WidgetKit budgets refreshes; it is not truly real-time).

## If the percentages look wrong

The exact JSON shape of `/api/oauth/usage` is undocumented, so the decoder in
[`Shared/UsageModels.swift`](Shared/UsageModels.swift) is deliberately tolerant.
On first run, open the app's **⋯ → "Rohdaten anzeigen"** to see the real
response, then adjust the `CodingKeys` / `UsageWindow` decoding to match (e.g. if
`utilization` is named differently or is a 0–1 fraction vs a 0–100 percent).

## Making it yours

Bundle IDs, the App Group, and the Keychain group are hardcoded to
`com.julianbelting.*` in [`project.yml`](project.yml),
[`Shared/Constants.swift`](Shared/Constants.swift) and the two `.entitlements`
files. Change them consistently if you want your own identifiers, then re-run
`xcodegen generate`.

## License

Personal project. Use at your own risk.
