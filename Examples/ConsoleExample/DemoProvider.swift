import Foundation
import AuthKitCore

/// An in-memory `AuthProvider` used only by the console example, so the demo
/// can run headless with no backend and no network flakiness. It behaves
/// like a real provider: it validates credentials, issues short-lived access
/// tokens, and mints a brand-new token every time AuthKit asks it to refresh
/// — which is exactly how the automatic-refresh path gets exercised below.
final class DemoProvider: AuthProvider, @unchecked Sendable {
    let id = AuthProviderID(rawValue: "demo")

    private let accessTokenLifetime: TimeInterval
    private var issueCount = 0
    private let lock = NSLock()

    init(accessTokenLifetime: TimeInterval) {
        self.accessTokenLifetime = accessTokenLifetime
    }

    func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let creds = credentials as? DemoCredentials else {
            throw AuthError.invalidCredentials
        }
        guard creds.username == "demo", creds.password == "password" else {
            throw AuthError.invalidCredentials
        }
        return issueTokenSet()
    }

    func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        guard refreshToken == "demo-refresh-token" else {
            throw AuthError.refreshFailed("unknown refresh token")
        }
        return issueTokenSet()
    }

    private func issueTokenSet() -> AuthTokenSet {
        lock.lock()
        issueCount += 1
        let n = issueCount
        lock.unlock()

        return AuthTokenSet(
            accessToken: "demo-access-token-#\(n)",
            refreshToken: "demo-refresh-token",
            expiresAt: Date().addingTimeInterval(accessTokenLifetime),
            user: AuthUser(
                id: "demo-user-1",
                providerID: id,
                displayName: "Demo User",
                email: "demo@example.com"
            )
        )
    }
}

struct DemoCredentials: AuthCredentials {
    let username: String
    let password: String
}
