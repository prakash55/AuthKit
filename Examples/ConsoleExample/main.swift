import Foundation
import Combine
import AuthKitCore

// A headless walkthrough of everything AuthKit does for you, printed as it
// happens. Run with:  swift run AuthKitConsoleExample
//
// It uses DemoProvider (in-memory, no backend) so it runs anywhere, but the
// AuthManager, token store, refresh scheduler, and state publisher are the
// real ones from AuthKitCore.

let demoProviderID = AuthProviderID(rawValue: "demo")
var cancellables = Set<AnyCancellable>()

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("[\(stamp)] \(message)")
}

func describe(_ state: AuthState) -> String {
    switch state {
    case .signedOut: return "signedOut"
    case .authenticating: return "authenticating"
    case .authenticated(let user): return "authenticated(\(user.email ?? user.id))"
    case .refreshing(let user): return "refreshing(\(user.email ?? user.id))"
    case .error(let error): return "error(\(error.localizedDescription))"
    }
}

// A short access-token lifetime + short refresh lead time so the automatic
// silent refresh happens within a few seconds instead of an hour.
let accessTokenLifetime: TimeInterval = 4
let manager = AuthManager(
    tokenStoreService: "com.authkit.console-example",
    refreshLeadTime: 2
)

// Observe the state stream — this is the ONE thing a real app's UI subscribes
// to. Everything else below just causes these transitions to fire.
manager.authStatePublisher
    .sink { state in
        log("state → \(describe(state))")
    }
    .store(in: &cancellables)

let demoProvider = DemoProvider(accessTokenLifetime: accessTokenLifetime)

// Clean slate in case a previous run left a session in the Keychain.
await manager.signOut()

log("1) configure() with the demo provider")
manager.configure(providers: [demoProvider])

log("2) signIn() with valid credentials")
do {
    let user = try await manager.signIn(
        using: demoProviderID,
        credentials: DemoCredentials(username: "demo", password: "password")
    )
    log("   signIn returned user: \(user.email ?? user.id)")
} catch {
    log("   signIn failed: \(error.localizedDescription)")
    exit(1)
}

log("3) accessToken() right after sign-in (should be cached, no refresh)")
if let token = try? await manager.accessToken() {
    log("   got token: \(token)")
}

log("4) waiting \(Int(accessTokenLifetime + 2))s — the refresh scheduler should fire on its own...")
try? await Task.sleep(nanoseconds: UInt64((accessTokenLifetime + 2) * 1_000_000_000))

log("5) accessToken() again — token number should have increased via silent refresh")
if let token = try? await manager.accessToken() {
    log("   got token: \(token)")
}

log("6) demonstrate rejected credentials")
do {
    _ = try await manager.signIn(
        using: demoProviderID,
        credentials: DemoCredentials(username: "demo", password: "wrong")
    )
} catch {
    log("   correctly rejected: \(error.localizedDescription)")
}

log("7) signOut()")
await manager.signOut()

log("8) accessToken() after sign-out should throw notAuthenticated")
do {
    _ = try await manager.accessToken()
    log("   ERROR: expected notAuthenticated")
} catch {
    log("   correctly threw: \(error.localizedDescription)")
}

log("done — full lifecycle verified")
exit(0)
