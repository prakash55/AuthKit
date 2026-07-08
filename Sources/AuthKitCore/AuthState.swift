import Foundation

/// Broadcast continuously by `AuthManager.authStatePublisher`. This is the
/// only thing most of the app needs to observe — it never needs to know
/// about tokens, expiry, or which provider is active.
public enum AuthState: Equatable, Sendable {
    case signedOut
    case authenticating
    case authenticated(AuthUser)
    /// Transient: the access token expired and a silent refresh is in
    /// flight. UI typically ignores this and keeps showing authenticated
    /// content; it exists for callers that want a loading affordance.
    case refreshing(AuthUser)
    case error(AuthError)

    public var user: AuthUser? {
        switch self {
        case .authenticated(let user), .refreshing(let user):
            return user
        case .signedOut, .authenticating, .error:
            return nil
        }
    }

    public static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.signedOut, .signedOut), (.authenticating, .authenticating):
            return true
        case (.authenticated(let l), .authenticated(let r)):
            return l == r
        case (.refreshing(let l), .refreshing(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}
