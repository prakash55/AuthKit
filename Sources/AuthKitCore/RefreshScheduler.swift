import Foundation

/// Watches the active token's expiry and refreshes before it actually
/// expires, and de-dupes reactive refresh calls (e.g. several requests
/// hitting a 401 at once should trigger exactly one network call).
/// Internal — `AuthManager` is the only thing that talks to this.
actor RefreshScheduler {
    private let leadTime: TimeInterval
    private var timerTask: Task<Void, Never>?
    private var inFlightRefresh: Task<AuthTokenSet, Error>?

    init(leadTime: TimeInterval = 60) {
        self.leadTime = leadTime
    }

    /// Arms a one-shot timer that fires `leadTime` seconds before
    /// `tokenSet.expiresAt`. Call again after every successful refresh to
    /// re-arm for the new expiry.
    func armTimer(
        for tokenSet: AuthTokenSet,
        provider: any AuthProvider,
        onResult: @escaping @Sendable (Result<AuthTokenSet, AuthError>) -> Void
    ) {
        timerTask?.cancel()
        guard tokenSet.refreshToken != nil else { return }

        let delay = max(1, tokenSet.expiresAt.addingTimeInterval(-leadTime).timeIntervalSinceNow)
        timerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            do {
                let refreshed = try await self.refreshNow(tokenSet: tokenSet, provider: provider)
                onResult(.success(refreshed))
            } catch let error as AuthError {
                onResult(.failure(error))
            } catch {
                onResult(.failure(.refreshFailed(error.localizedDescription)))
            }
        }
    }

    /// Reactive path: called directly by `AuthManager.accessToken()` when a
    /// token is already past (or about to hit) expiry, and internally by the
    /// timer above. Concurrent callers share one in-flight network call.
    func refreshNow(tokenSet: AuthTokenSet, provider: any AuthProvider) async throws -> AuthTokenSet {
        if let inFlightRefresh {
            return try await inFlightRefresh.value
        }
        guard let refreshToken = tokenSet.refreshToken else {
            throw AuthError.refreshFailed("no refresh token available")
        }

        let task = Task<AuthTokenSet, Error> {
            try await provider.refresh(using: refreshToken)
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }

        do {
            return try await task.value
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.refreshFailed(error.localizedDescription)
        }
    }

    func invalidate() {
        timerTask?.cancel()
        timerTask = nil
        inFlightRefresh = nil
    }
}
