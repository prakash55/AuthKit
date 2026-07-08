import XCTest
@testable import AuthKitCore

final class AuthManagerTests: XCTestCase {
    private func makeManager(refreshLeadTime: TimeInterval = 60) -> AuthManager {
        // Unique Keychain service per test so tests don't see each other's state.
        AuthManager(tokenStoreService: "com.authkit.tests.\(UUID().uuidString)", refreshLeadTime: refreshLeadTime)
    }

    func test_signIn_publishesAuthenticatedState() async throws {
        let manager = makeManager()
        let provider = MockAuthProvider(authenticateResult: .success(.mock(userID: "abc")))
        manager.configure(providers: [provider])

        let user = try await manager.signIn(using: .emailPassword, credentials: NoCredentials())

        XCTAssertEqual(user.id, "abc")
        XCTAssertEqual(manager.currentUser?.id, "abc")
        XCTAssertEqual(manager.authState, .authenticated(user))
    }

    func test_signUp_publishesAuthenticatedState() async throws {
        let manager = makeManager()
        let provider = MockAuthProvider(
            authenticateResult: .failure(.invalidCredentials),
            registerResult: .success(.mock(userID: "new-user"))
        )
        manager.configure(providers: [provider])

        let user = try await manager.signUp(using: .emailPassword, credentials: NoCredentials())

        XCTAssertEqual(user.id, "new-user")
        XCTAssertEqual(manager.currentUser?.id, "new-user")
        XCTAssertEqual(manager.authState, .authenticated(user))
        XCTAssertEqual(provider.registerCallCount, 1)
    }

    func test_signUp_whenProviderDoesNotSupportIt_throwsSignUpNotSupported() async {
        let manager = makeManager()
        // registerResult nil → provider reports sign-up unsupported (like Google/Facebook).
        let provider = MockAuthProvider(id: .google, authenticateResult: .success(.mock()))
        manager.configure(providers: [provider])

        do {
            _ = try await manager.signUp(using: .google, credentials: NoCredentials())
            XCTFail("expected signUpNotSupported to be thrown")
        } catch AuthError.signUpNotSupported(let id) {
            XCTAssertEqual(id, .google)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        if case .error = manager.authState {} else {
            XCTFail("expected .error state, got \(manager.authState)")
        }
    }

    func test_signIn_withUnregisteredProvider_throwsAndPublishesError() async {
        let manager = makeManager()
        manager.configure(providers: [])

        do {
            _ = try await manager.signIn(using: .google, credentials: NoCredentials())
            XCTFail("expected providerNotRegistered to be thrown")
        } catch AuthError.providerNotRegistered(let id) {
            XCTAssertEqual(id, .google)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        if case .error = manager.authState {} else {
            XCTFail("expected .error state, got \(manager.authState)")
        }
    }

    func test_signIn_withRejectedCredentials_propagatesInvalidCredentials() async {
        let manager = makeManager()
        let provider = MockAuthProvider(authenticateResult: .failure(.invalidCredentials))
        manager.configure(providers: [provider])

        do {
            _ = try await manager.signIn(using: .emailPassword, credentials: NoCredentials())
            XCTFail("expected invalidCredentials to be thrown")
        } catch AuthError.invalidCredentials {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_signOut_clearsSessionAndNotifiesProvider() async throws {
        let manager = makeManager()
        let provider = MockAuthProvider(authenticateResult: .success(.mock()))
        manager.configure(providers: [provider])
        _ = try await manager.signIn(using: .emailPassword, credentials: NoCredentials())

        await manager.signOut()

        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(manager.authState, .signedOut)
        XCTAssertEqual(provider.signOutCallCount, 1)

        do {
            _ = try await manager.accessToken()
            XCTFail("expected notAuthenticated after sign-out")
        } catch AuthError.notAuthenticated {
            // expected
        }
    }

    func test_accessToken_returnsCachedTokenWhenNotExpired() async throws {
        let manager = makeManager()
        let provider = MockAuthProvider(authenticateResult: .success(.mock(accessToken: "fresh-token", expiresIn: 3600)))
        manager.configure(providers: [provider])
        _ = try await manager.signIn(using: .emailPassword, credentials: NoCredentials())

        let token = try await manager.accessToken()

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(provider.refreshCallCount, 0)
    }

    func test_accessToken_refreshesExpiredTokenTransparently() async throws {
        let manager = makeManager()
        let provider = MockAuthProvider(
            authenticateResult: .success(.mock(accessToken: "expired-token", expiresIn: -10)),
            refreshResult: .success(.mock(accessToken: "refreshed-token", expiresIn: 3600))
        )
        manager.configure(providers: [provider])
        _ = try await manager.signIn(using: .emailPassword, credentials: NoCredentials())

        let token = try await manager.accessToken()

        XCTAssertEqual(token, "refreshed-token")
        XCTAssertEqual(provider.refreshCallCount, 1)
        XCTAssertEqual(manager.currentUser?.id, "user-1")
    }

    func test_configure_restoresPreviousSessionFromKeychain() async throws {
        let service = "com.authkit.tests.\(UUID().uuidString)"
        let provider = MockAuthProvider(authenticateResult: .success(.mock(expiresIn: 3600, userID: "restored-user")))

        let firstManager = AuthManager(tokenStoreService: service)
        firstManager.configure(providers: [provider])
        _ = try await firstManager.signIn(using: .emailPassword, credentials: NoCredentials())

        // Simulate a fresh launch: a brand new AuthManager instance backed by the same Keychain service.
        let secondManager = AuthManager(tokenStoreService: service)
        secondManager.configure(providers: [provider])

        // configure() restores asynchronously; poll briefly for the published state to settle.
        for _ in 0..<50 {
            if secondManager.currentUser != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(secondManager.currentUser?.id, "restored-user")
    }
}
