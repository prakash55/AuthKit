import Foundation
@testable import AuthKitCore

final class MockAuthProvider: AuthProvider, @unchecked Sendable {
    let id: AuthProviderID
    var authenticateResult: Result<AuthTokenSet, AuthError>
    var refreshResult: Result<AuthTokenSet, AuthError>
    private(set) var refreshCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        id: AuthProviderID = .emailPassword,
        authenticateResult: Result<AuthTokenSet, AuthError>,
        refreshResult: Result<AuthTokenSet, AuthError>? = nil
    ) {
        self.id = id
        self.authenticateResult = authenticateResult
        self.refreshResult = refreshResult ?? authenticateResult
    }

    func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        try authenticateResult.get()
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
