import Foundation

/// The single extension point of AuthKit. To add a new way to sign in
/// (Sign in with Apple, SAML, a corporate SSO, biometric re-auth, ...),
/// create one type that conforms to this protocol and register an instance
/// with `AuthManager.configure(providers:)`. Nothing else in the package
/// needs to change.
public protocol AuthProvider: Sendable {
    var id: AuthProviderID { get }

    /// Exchanges provider-specific credentials for a normalized token set.
    /// Implementations should throw `AuthError.invalidCredentials` if the
    /// `credentials` value isn't the concrete type this provider expects.
    func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet

    /// Creates a new account and returns a token set for it, so the user is
    /// signed in immediately after signing up. Optional: only providers where
    /// registration is a distinct operation implement this (email/password,
    /// custom REST). For OAuth providers like Google/Facebook the first
    /// `authenticate` already creates the account, so the default throws
    /// `AuthError.signUpNotSupported` and callers use `signIn` instead.
    func register(with credentials: any AuthCredentials) async throws -> AuthTokenSet

    /// Exchanges a refresh token for a new token set. Called only by
    /// AuthKitCore's internal `RefreshScheduler` — never by app code.
    func refresh(using refreshToken: String) async throws -> AuthTokenSet

    /// Revokes/clears any provider-side session (e.g. GIDSignIn.sharedInstance.signOut()).
    /// AuthKitCore always clears its own Keychain entry regardless of what this does.
    func signOut(userID: String) async
}

public extension AuthProvider {
    // Most providers don't hold provider-side session state worth revoking
    // beyond what AuthKitCore already clears, so make this opt-in.
    func signOut(userID: String) async {}

    // Registration isn't a distinct operation for every provider (OAuth
    // providers create the account on first sign-in), so it's opt-in.
    func register(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        throw AuthError.signUpNotSupported(id)
    }
}
