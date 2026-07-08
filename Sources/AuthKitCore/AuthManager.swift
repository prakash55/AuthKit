import Foundation
import Combine

/// The only public entry point of AuthKit. An app imports `AuthKitCore` plus
/// whichever provider modules it needs, registers providers once at launch,
/// and from then on only ever calls `signIn`, `signOut`, reads `currentUser`,
/// or observes `authStatePublisher`. Token storage, expiry tracking, and
/// silent refresh all happen inside this type and are never exposed.
public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()

    private let stateSubject = CurrentValueSubject<AuthState, Never>(.signedOut)
    private let tokenStore: TokenStore
    private let refreshScheduler: RefreshScheduler
    private let lock = NSLock()

    private var providers: [AuthProviderID: any AuthProvider] = [:]
    private var activeProviderID: AuthProviderID?
    private var activeTokenSet: AuthTokenSet?
    private var didRestoreSession = false
    private var restoreTask: Task<Void, Never>?

    public var authState: AuthState { stateSubject.value }
    public var authStatePublisher: AnyPublisher<AuthState, Never> { stateSubject.eraseToAnyPublisher() }
    public var currentUser: AuthUser? { stateSubject.value.user }

    /// Most apps use `AuthManager.shared`. Create your own instance only if
    /// you need a custom Keychain service name (e.g. to isolate multiple
    /// logical sessions) or a different refresh lead time.
    /// - Parameters:
    ///   - tokenStoreService: Keychain service string tokens are stored under.
    ///   - refreshLeadTime: how many seconds before expiry the silent refresh
    ///     timer fires. Default 60.
    public init(tokenStoreService: String = "com.authkit.tokens", refreshLeadTime: TimeInterval = 60) {
        self.tokenStore = TokenStore(service: tokenStoreService)
        self.refreshScheduler = RefreshScheduler(leadTime: refreshLeadTime)
    }

    /// Registers the providers this app supports. Call once at launch, e.g.
    /// `AuthManager.shared.configure(providers: [EmailPasswordProvider(baseURL: ...), GoogleAuthProvider()])`.
    /// Also attempts to restore a previously signed-in session from the
    /// Keychain, refreshing it first if it's expired.
    public func configure(providers: [any AuthProvider]) {
        lock.lock()
        for provider in providers {
            self.providers[provider.id] = provider
        }
        let shouldRestore = !didRestoreSession
        didRestoreSession = true
        lock.unlock()

        guard shouldRestore else { return }
        setRestoreTask(Task { await self.restoreSessionIfAvailable() })
    }

    /// Starts a sign-in with the given provider. `credentials` must be the
    /// concrete type that provider expects (e.g. `EmailPasswordCredentials`
    /// for `AuthKitEmailPassword`, `NoCredentials` for providers that drive
    /// their own UI like Google/Facebook).
    @discardableResult
    public func signIn(using providerID: AuthProviderID, credentials: any AuthCredentials) async throws -> AuthUser {
        // If a cold-launch session restore is still in flight, let it finish
        // first so it can't race with (and clobber, or be clobbered by) this
        // explicit sign-in.
        await waitForPendingRestore()

        guard let provider = provider(for: providerID) else {
            let error = AuthError.providerNotRegistered(providerID)
            stateSubject.send(.error(error))
            throw error
        }

        stateSubject.send(.authenticating)
        do {
            let tokenSet = try await provider.authenticate(with: credentials)
            try await activate(tokenSet: tokenSet, providerID: providerID, provider: provider)
            return tokenSet.user
        } catch let error as AuthError {
            stateSubject.send(.error(error))
            throw error
        } catch {
            let wrapped = AuthError.network(error.localizedDescription)
            stateSubject.send(.error(wrapped))
            throw wrapped
        }
    }

    /// Signs out of the active session: revokes provider-side state (if the
    /// provider implements it), clears the Keychain, and publishes `.signedOut`.
    public func signOut() async {
        await refreshScheduler.invalidate()
        let session = activeSession()
        if let (providerID, _) = session, let user = currentUser, let provider = provider(for: providerID) {
            await provider.signOut(userID: user.id)
        }
        if let (providerID, _) = session {
            await tokenStore.clear(for: providerID)
        }
        setActiveSession(nil)
        stateSubject.send(.signedOut)
    }

    /// Returns a valid access token for the app's own API calls, refreshing
    /// first if the current one is expired or about to be. This is the one
    /// method most app networking code needs — it never has to check expiry
    /// itself.
    public func accessToken() async throws -> String {
        await waitForPendingRestore()

        guard let (providerID, tokenSet) = activeSession(), let provider = provider(for: providerID) else {
            throw AuthError.notAuthenticated
        }

        guard tokenSet.needsRefresh(leadTime: 0) else {
            return tokenSet.accessToken
        }

        let refreshed = try await refreshScheduler.refreshNow(tokenSet: tokenSet, provider: provider)
        try await activate(tokenSet: refreshed, providerID: providerID, provider: provider)
        return refreshed.accessToken
    }

    /// Convenience for building an authenticated request without the app
    /// ever touching the token directly.
    public func authorizedRequest(for url: URL) async throws -> URLRequest {
        let token = try await accessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Private

    private func provider(for id: AuthProviderID) -> (any AuthProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return providers[id]
    }

    private func activeSession() -> (AuthProviderID, AuthTokenSet)? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = activeProviderID, let tokenSet = activeTokenSet else { return nil }
        return (id, tokenSet)
    }

    private func setActiveSession(_ session: (AuthProviderID, AuthTokenSet)?) {
        lock.lock()
        activeProviderID = session?.0
        activeTokenSet = session?.1
        lock.unlock()
    }

    private func setRestoreTask(_ task: Task<Void, Never>?) {
        lock.lock()
        restoreTask = task
        lock.unlock()
    }

    private func waitForPendingRestore() async {
        let task: Task<Void, Never>? = {
            lock.lock()
            defer { lock.unlock() }
            return restoreTask
        }()
        await task?.value
    }

    private func activate(tokenSet: AuthTokenSet, providerID: AuthProviderID, provider: any AuthProvider) async throws {
        try await tokenStore.save(tokenSet, for: providerID)
        setActiveSession((providerID, tokenSet))
        stateSubject.send(.authenticated(tokenSet.user))

        await refreshScheduler.armTimer(for: tokenSet, provider: provider) { [weak self] result in
            guard let self else { return }
            Task {
                await self.handleScheduledRefresh(result, providerID: providerID, provider: provider)
            }
        }
    }

    private func handleScheduledRefresh(
        _ result: Result<AuthTokenSet, AuthError>,
        providerID: AuthProviderID,
        provider: any AuthProvider
    ) async {
        // Ignore results from a provider/session that's no longer active
        // (e.g. the user signed out while a refresh was in flight).
        guard activeSession()?.0 == providerID else { return }

        switch result {
        case .success(let refreshed):
            try? await activate(tokenSet: refreshed, providerID: providerID, provider: provider)
        case .failure(let error):
            stateSubject.send(.error(error))
        }
    }

    private func restoreSessionIfAvailable() async {
        guard let (providerID, tokenSet) = await tokenStore.loadMostRecent(),
              let provider = provider(for: providerID) else {
            return
        }

        if tokenSet.isExpired {
            guard tokenSet.refreshToken != nil else {
                await tokenStore.clear(for: providerID)
                return
            }
            do {
                let refreshed = try await refreshScheduler.refreshNow(tokenSet: tokenSet, provider: provider)
                // Nothing else calls signIn/accessToken while a restore is in
                // flight (both wait on this task), so there's no legitimate
                // session to clobber here — this is just cheap insurance.
                guard activeSession() == nil else { return }
                try await activate(tokenSet: refreshed, providerID: providerID, provider: provider)
            } catch {
                await tokenStore.clear(for: providerID)
            }
        } else {
            guard activeSession() == nil else { return }
            try? await activate(tokenSet: tokenSet, providerID: providerID, provider: provider)
        }
    }
}
