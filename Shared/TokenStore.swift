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

/// Shared keychain plumbing. Every store keeps exactly one generic-password
/// item per service, so writes UPDATE in place: the old delete-then-add left the
/// user with nothing at all whenever the add failed (locked keychain, missing
/// entitlement) — for the token item that means a silent, unexplained sign-out.
enum Keychain {
    @discardableResult
    static func save(_ data: Data, query base: [String: Any]) -> OSStatus {
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }

    static func load(_ base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        else { return nil }
        return result as? Data
    }

    static func delete(_ base: [String: Any]) {
        SecItemDelete(base as CFDictionary)
    }

    /// A human-readable reason, for the few places where a failed write has to
    /// be explained to the user rather than silently swallowed.
    static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

enum TokenStore {
    private static let account = "tokens"

    /// Returns `errSecSuccess` on success. Callers on the login path surface a
    /// failure; a lost token write is otherwise invisible until the next launch.
    @discardableResult
    static func save(_ tokens: TokenSet) -> OSStatus {
        guard let data = try? JSONEncoder().encode(tokens) else { return errSecParam }
        return Keychain.save(data, query: baseQuery())
    }

    static func load() -> TokenSet? {
        guard let data = Keychain.load(baseQuery()) else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    static func clear() {
        Keychain.delete(baseQuery())
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
