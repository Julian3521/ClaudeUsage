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
3. Click it → **Anmelden** → **Token** tab. The usage endpoint requires the
   `user:profile` scope, which your existing Claude Code login already has, so the
   simplest path is to paste that token. The window shows a one-line command that
   copies it to your clipboard (`security find-generic-password -s "Claude
   Code-credentials" -w | python3 -c "…accessToken…" | pbcopy`). Paste it (⌘V) →
   **Speichern & verbinden**. (A **Browser** OAuth tab exists too, but Google SSO
   is blocked in embedded web views, and `claude setup-token` mints an
   inference-only token the usage endpoint rejects with 403.)
4. Add the widget: right-click the desktop → *Edit Widgets* (or open Notification
   Center → *Edit Widgets*) → search **Claude Usage** → pick Small / Medium / Large.

## How it works

```text
Login (token paste)  ─▶ existing Claude Code token (Keychain, has user:profile)
Login (browser OAuth) ─▶ claude.ai/oauth/authorize (PKCE) → platform.claude.com/v1/oauth/token
App  ─▶ api.anthropic.com/api/oauth/usage   (Bearer + anthropic-beta: oauth-2025-04-20)
        → five_hour / seven_day → rings & bars → snapshot (Keychain) → widget reads it
```

- **`Shared/`** — models, OAuth (PKCE), Keychain token + snapshot store, usage
  API, shared SwiftUI ring/bar views. Swift 6 language mode, `@Observable`.
- **`App/`** — `MenuBarExtra` app + login window + Settings window. The app is
  the single fetcher; a periodic timer refreshes the value and reloads the widget.
- **`Widget/`** — WidgetKit provider + Small/Medium/Large views. It only renders
  the snapshot the app writes (no network), so it never adds to endpoint load.

**Settings** (menu bar → ⋯ → Settings…) with a live preview:

- **Menu bar** — which limit to show (highest / session / weekly / **both**) and
  how (**progress bar** and/or **percentage**, independently).
- **General** — **launch at login**, refresh interval (10/20/30/60 min), and a
  **notification** when any limit reaches 90 %.
- **Details** — show the Opus & Sonnet weekly limits and extra-usage **spend (€)**.

**Localized in English and German.**

## Distribution

For a downloadable, double-click-to-run build, `scripts/release.sh` archives,
signs (Developer ID), builds a DMG, and notarizes it. One-time setup: create a
*Developer ID Application* certificate and store notary credentials (see the
comments at the top of the script). Then attach the DMG to a GitHub release.

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
