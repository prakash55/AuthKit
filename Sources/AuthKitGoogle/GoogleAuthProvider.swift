import Foundation
import UIKit
import GoogleSignIn
import AuthKitCore

/// Google Sign-In provider. iOS-only (GoogleSignIn-iOS doesn't ship a macOS
/// target) — apps that only need macOS shouldn't add this product.
///
/// Google's SDK manages its own token lifecycle internally (`GIDGoogleUser`
/// caches and silently refreshes its own tokens), so this provider is
/// mostly a thin adapter: `authenticate` presents Google's sign-in sheet via
/// `GIDSignIn`, and `refresh` asks the SDK to refresh in place rather than
/// re-deriving everything from a bare refresh-token string.
public final class GoogleAuthProvider: AuthProvider, Sendable {
    public let id: AuthProviderID = .google

    /// - Parameter clientID: your OAuth client ID from the Google Cloud console.
    public init(clientID: String) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    @MainActor
    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let presentingViewController = AuthPresentationContext.topMostViewController() else {
            throw AuthError.invalidServerResponse
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            return Self.tokenSet(from: result.user)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notAuthenticated
        }
        return try await withCheckedThrowingContinuation { continuation in
            currentUser.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: AuthError.refreshFailed(error.localizedDescription))
                } else if let user {
                    continuation.resume(returning: Self.tokenSet(from: user))
                } else {
                    continuation.resume(throwing: AuthError.refreshFailed("GoogleSignIn returned no user"))
                }
            }
        }
    }

    public func signOut(userID: String) async {
        GIDSignIn.sharedInstance.signOut()
    }

    private static func tokenSet(from googleUser: GIDGoogleUser) -> AuthTokenSet {
        let profile = googleUser.profile
        let user = AuthUser(
            id: googleUser.userID ?? googleUser.accessToken.tokenString,
            providerID: .google,
            displayName: profile?.name,
            email: profile?.email,
            photoURL: profile?.imageURL(withDimension: 200)
        )
        return AuthTokenSet(
            accessToken: googleUser.accessToken.tokenString,
            refreshToken: googleUser.refreshToken.tokenString,
            expiresAt: googleUser.accessToken.expirationDate ?? Date().addingTimeInterval(3600),
            user: user
        )
    }
}
