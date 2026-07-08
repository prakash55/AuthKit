import Foundation

/// The result of a successful authentication or refresh call.
///
/// `refreshToken` is `public` because `AuthProvider` conformances live in
/// separate modules (AuthKitGoogle, AuthKitEmailPassword, ...) and must be
/// able to construct this type. That is a different boundary from the one
/// that matters for security: `AuthManager`'s public API (`currentUser`,
/// `authState`, `authStatePublisher`) never returns an `AuthTokenSet`, so an
/// app that only imports AuthKitCore + a provider has no code path that ever
/// reads a refresh token. Only `TokenStore` and `RefreshScheduler`, both
/// internal, do.
public struct AuthTokenSet: Sendable, Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let user: AuthUser

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// True once we're inside the refresh window, even though the token is
    /// technically still valid. `RefreshScheduler` uses this to refresh
    /// silently before anything actually fails.
    func needsRefresh(leadTime: TimeInterval) -> Bool {
        Date() >= expiresAt.addingTimeInterval(-leadTime)
    }
}
