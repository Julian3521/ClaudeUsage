import Foundation

/// Central configuration. All values were taken from the public Claude Code CLI
/// OAuth flow — they are public client identifiers, not secrets. This is an
/// UNOFFICIAL/undocumented flow and may break if Anthropic changes it.
enum Config {
    // OAuth (Claude Code public client) — used for token refresh.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"

    // Usage endpoint (same one `claude /usage` calls)
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let oauthBetaHeader = "oauth-2025-04-20"

    /// Opened when the user clicks the widget or the "Open usage" menu item.
    static let usagePageURL = URL(string: "https://claude.ai/settings/usage")!

    /// Messages endpoint + tiny model used to "anchor" a new 5h window.
    static let messagesURL = "https://api.anthropic.com/v1/messages"
    static let pingModel = "claude-haiku-4-5-20251001"
    /// OAuth inference requires the Claude Code identity in the system prompt.
    static let claudeCodeSystemPrompt = "You are Claude Code, Anthropic's official CLI for Claude."

    // Sharing between the app and the widget extension happens entirely through
    // the Keychain. Both targets list the same single entry in
    // `keychain-access-groups`, so items saved WITHOUT an explicit access group
    // default to it and are visible to both. Service names below distinguish the
    // stored items within that shared group.
    static let keychainService = "ClaudeUsage.oauth"          // OAuth tokens
    static let keychainSnapshotService = "ClaudeUsage.snapshot"  // cached usage
    static let keychainSettingsService = "ClaudeUsage.settings"  // user settings
    static let keychainHistoryService = "ClaudeUsage.history"    // usage history

    /// Refresh the widget at most this often (seconds). WidgetKit budgets refreshes.
    static let widgetRefreshInterval: TimeInterval = 20 * 60

    /// Reuse a cached snapshot newer than this instead of hitting the network,
    /// so relaunches / rapid refreshes don't trip the endpoint's rate limit.
    static let minFetchInterval: TimeInterval = 120

    /// Lowest allowed auto-refresh interval (minutes). The usage endpoint
    /// rate-limits aggressively; faster polling reliably triggers 429s.
    static let minRefreshMinutes = 15
}
