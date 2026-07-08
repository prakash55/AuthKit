import Foundation
import UIKit
import FBSDKLoginKit
import FBSDKCoreKit
import AuthKitCore

/// Facebook Login provider. iOS-only, same reasoning as `AuthKitGoogle`.
///
/// Facebook doesn't expose a separate refresh token the way OAuth servers
/// typically do — `AccessToken` is long-lived (~60 days) and the SDK
/// refreshes it in place via `AccessToken.refreshCurrentAccessToken`. So
/// `refresh(using:)` ignores the string AuthKit hands it and just asks the
/// SDK to refresh its current token, matching how `AuthKitGoogle` defers to
/// `GIDGoogleUser.refreshTokensIfNeeded`.
public final class FacebookAuthProvider: AuthProvider, Sendable {
    public let id: AuthProviderID = .facebook
    private let permissions: [String]

    public init(permissions: [String] = ["public_profile", "email"]) {
        self.permissions = permissions
    }

    @MainActor
    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let presentingViewController = AuthPresentationContext.topMostViewController() else {
            throw AuthError.invalidServerResponse
        }

        let loginManager = LoginManager()
        let token: AccessToken = try await withCheckedThrowingContinuation { continuation in
            loginManager.logIn(permissions: permissions, from: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: AuthError.network(error.localizedDescription))
                } else if let result, result.isCancelled {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let token = result?.token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AuthError.invalidServerResponse)
                }
            }
        }
        return try await Self.tokenSet(from: token)
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        try await withCheckedThrowingContinuation { continuation in
            AccessToken.refreshCurrentAccessToken { _, _, error in
                if let error {
                    continuation.resume(throwing: AuthError.refreshFailed(error.localizedDescription))
                    return
                }
                guard let token = AccessToken.current else {
                    continuation.resume(throwing: AuthError.refreshFailed("no current Facebook access token"))
                    return
                }
                Task {
                    do {
                        continuation.resume(returning: try await Self.tokenSet(from: token))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    public func signOut(userID: String) async {
        LoginManager().logOut()
    }

    private static func tokenSet(from token: AccessToken) async throws -> AuthTokenSet {
        let profile = try await fetchProfile(accessToken: token)
        return AuthTokenSet(
            accessToken: token.tokenString,
            refreshToken: nil,
            expiresAt: token.expirationDate,
            user: profile
        )
    }

    private static func fetchProfile(accessToken: AccessToken) async throws -> AuthUser {
        try await withCheckedThrowingContinuation { continuation in
            let request = GraphRequest(
                graphPath: "me",
                parameters: ["fields": "id,name,email,picture.type(large)"],
                tokenString: accessToken.tokenString,
                version: nil,
                httpMethod: .get
            )
            request.start { _, result, error in
                if let error {
                    continuation.resume(throwing: AuthError.network(error.localizedDescription))
                    return
                }
                let fields = result as? [String: Any]
                let id = (fields?["id"] as? String) ?? accessToken.userID ?? ""
                let pictureData = (fields?["picture"] as? [String: Any])?["data"] as? [String: Any]
                let photoURL = (pictureData?["url"] as? String).flatMap(URL.init(string:))
                continuation.resume(returning: AuthUser(
                    id: id,
                    providerID: .facebook,
                    displayName: fields?["name"] as? String,
                    email: fields?["email"] as? String,
                    photoURL: photoURL
                ))
            }
        }
    }
}
