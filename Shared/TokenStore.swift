import Foundation
import Security

/// OAuth tokens persisted in the Keychain, shared between the app and the
/// widget extension via the keychain access group (see entitlements).
struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Treat as expired 60s early to avoid races.
        return Date() >= expiresAt.addingTimeInterval(-60)
    }
}

enum TokenStore {
    private static let account = "tokens"

    static func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }

        let base = baseQuery()
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> TokenSet? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        // No explicit access group: items default to the single entry in the
        // `keychain-access-groups` entitlement, which both targets share.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainService,
            kSecAttrAccount as String: account,
            // Required on macOS so the keychain access group (sharing with the
            // widget) behaves like iOS. Harmless on iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
