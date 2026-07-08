import Foundation
#if canImport(Security)
import Security
#endif

/// Persists `AuthTokenSet`s in the Keychain, one entry per provider,
/// encrypted at rest by the OS and readable only after first unlock.
/// This type is `internal` — nothing outside AuthKitCore ever touches
/// tokens directly.
///
/// Which provider is "active" is tracked with a small marker in
/// `UserDefaults` (just a provider id string, not a secret) rather than by
/// enumerating every Keychain item and comparing modification dates.
/// Bulk Keychain queries (`kSecMatchLimitAll`) depend on a securityd/XPC
/// round trip that isn't available in every host environment (e.g. some
/// sandboxed CI runners); exact single-item lookups (what every other
/// method here does) don't have that dependency.
actor TokenStore {
    private let service: String
    private let activeProviderKey: String
    private let defaults: UserDefaults

    init(service: String = "com.authkit.tokens", defaults: UserDefaults = .standard) {
        self.service = service
        self.activeProviderKey = "\(service).activeProviderID"
        self.defaults = defaults
    }

    func save(_ tokenSet: AuthTokenSet, for providerID: AuthProviderID) throws {
        let data = try JSONEncoder().encode(tokenSet)

        var query = baseQuery(for: providerID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let deleteStatus = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AuthError.keychain(deleteStatus)
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthError.keychain(addStatus)
        }

        defaults.set(providerID.rawValue, forKey: activeProviderKey)
    }

    func load(for providerID: AuthProviderID) -> AuthTokenSet? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthTokenSet.self, from: data)
    }

    /// The session that was active when the app last quit — used to restore
    /// it on launch.
    func loadMostRecent() -> (AuthProviderID, AuthTokenSet)? {
        guard let rawProviderID = defaults.string(forKey: activeProviderKey) else {
            return nil
        }
        let providerID = AuthProviderID(rawValue: rawProviderID)
        guard let tokenSet = load(for: providerID) else { return nil }
        return (providerID, tokenSet)
    }

    func clear(for providerID: AuthProviderID) {
        SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        if defaults.string(forKey: activeProviderKey) == providerID.rawValue {
            defaults.removeObject(forKey: activeProviderKey)
        }
    }

    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: activeProviderKey)
    }

    private func baseQuery(for providerID: AuthProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.rawValue
        ]
    }
}
