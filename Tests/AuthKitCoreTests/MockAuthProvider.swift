import Foundation
@testable import AuthKitCore

final class MockAuthProvider: AuthProvider, @unchecked Sendable {
    let id: AuthProviderID
    var authenticateResult: Result<AuthTokenSet, AuthError>
    var refreshResult: Result<AuthTokenSet, AuthError>
    var registerResult: Result<AuthTokenSet, AuthError>?
    private(set) var refreshCallCount = 0
    private(set) var registerCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        id: AuthProviderID = .emailPassword,
        authenticateResult: Result<AuthTokenSet, AuthError>,
        refreshResult: Result<AuthTokenSet, AuthError>? = nil,
        registerResult: Result<AuthTokenSet, AuthError>? = nil
    ) {
        self.id = id
        self.authenticateResult = authenticateResult
        self.refreshResult = refreshResult ?? authenticateResult
        self.registerResult = registerResult
    }

    func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        try authenticateResult.get()
    }

    func register(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        registerCallCount += 1
        // Nil registerResult means "this provider doesn't support sign-up",
        // so fall back to the protocol default (throws signUpNotSupported).
        guard let registerResult else {
            throw AuthError.signUpNotSupported(id)
        }
        return try registerResult.get()
    }

    func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    func signOut(userID: String) async {
        signOutCallCount += 1
    }
}

extension AuthTokenSet {
    static func mock(
        accessToken: String = "access-123",
        refreshToken: String? = "refresh-123",
        expiresIn: TimeInterval = 3600,
        userID: String = "user-1",
        providerID: AuthProviderID = .emailPassword
    ) -> AuthTokenSet {
        AuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            user: AuthUser(id: userID, providerID: providerID, displayName: "Test User", email: "test@example.com")
        )
    }
}
