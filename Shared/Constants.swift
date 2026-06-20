import Foundation

/// Central configuration. All values were taken from the public Claude Code CLI
/// OAuth flow — they are public client identifiers, not secrets. This is an
/// UNOFFICIAL/undocumented flow and may break if Anthropic changes it.
enum Config {
    // OAuth (Claude Code public client)
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://platform.claude.com/oauth/authorize"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scopes = "user:profile user:inference"

    // Usage endpoint (same one `claude /usage` calls)
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let oauthBetaHeader = "oauth-2025-04-20"

    // Sharing between the app and the widget extension
    static let appGroup = "group.com.julianbelting.ClaudeUsage"
    /// Keychain access group: prefixed with the team id at build time. Because it
    /// is the only entry in `keychain-access-groups`, items saved WITHOUT an
    /// explicit access group default to it, so app + widget share them.
    static let keychainAccessGroup = "com.julianbelting.ClaudeUsage.shared"
    static let keychainService = "ClaudeUsage.oauth"

    /// Refresh the widget at most this often (seconds). WidgetKit budgets refreshes.
    static let widgetRefreshInterval: TimeInterval = 20 * 60
}
