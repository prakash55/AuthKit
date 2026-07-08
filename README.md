# AuthKit

A Swift package that owns authentication for your app end-to-end. You register
the sign-in methods you support, then observe a single continuously-published
auth state. Token storage, expiry tracking, and silent refresh all happen
inside the framework — once it's wired up, no other part of your app needs to
think about authentication.

## Design

Everything that varies between sign-in methods (Google vs. Facebook vs. email
vs. your own REST backend) lives behind one protocol, `AuthProvider`.
Everything that's the same regardless of method (Keychain storage, expiry
tracking, refresh, state broadcasting) lives once in `AuthKitCore`. Your app
talks to exactly one object: `AuthManager`.

```
Your app ──▶ AuthManager (only public entry point)
                 │
                 ├─▶ TokenStore        (Keychain, encrypted)
                 ├─▶ RefreshScheduler  (silent refresh before expiry)
                 ├─▶ state publisher   (Combine)
                 └─▶ AuthProvider      (pluggable: email, Google, Facebook, phone, custom…)
```

## Targets

The package is split so you only pull in the SDKs you actually use:

| Product | Depends on | Platforms |
|---|---|---|
| `AuthKitCore` | nothing (zero third-party deps) | iOS 15+, macOS 12+ |
| `AuthKitEmailPassword` | Core + Foundation | iOS, macOS |
| `AuthKitPhoneOTP` | Core + Foundation | iOS, macOS |
| `AuthKitRESTCustom` | Core + Foundation | iOS, macOS |
| `AuthKitGoogle` | Core + [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) | iOS |
| `AuthKitFacebook` | Core + [facebook-ios-sdk](https://github.com/facebook/facebook-ios-sdk) | iOS |

Import `AuthKitCore` plus only the provider modules you need.

## Installation

In your `Package.swift`:

```swift
.package(url: "https://github.com/prakash55/AuthKit.git", from: "1.0.0")
```

Then add the products you need to your target, e.g. `AuthKitCore` and
`AuthKitEmailPassword`.

## Usage

Register providers once at launch:

```swift
import AuthKitCore
import AuthKitEmailPassword

AuthManager.shared.configure(providers: [
    EmailPasswordProvider(baseURL: URL(string: "https://api.example.com")!)
])
```

Observe the auth state anywhere (this is all your UI needs):

```swift
AuthManager.shared.authStatePublisher
    .sink { state in
        switch state {
        case .signedOut:            // show login
        case .authenticated(let user), .refreshing(let user):  // show app
        case .authenticating:       // spinner
        case .error(let error):     // show message
        }
    }
    .store(in: &cancellables)
```

Sign in / out:

```swift
try await AuthManager.shared.signIn(
    using: .emailPassword,
    credentials: EmailPasswordCredentials(email: email, password: password)
)

await AuthManager.shared.signOut()
```

Make an authenticated request without ever touching the token (AuthKit
refreshes it first if needed):

```swift
let request = try await AuthManager.shared.authorizedRequest(for: url)
let (data, _) = try await URLSession.shared.data(for: request)
```

### The public surface, in full

`AuthManager` exposes only: `configure(providers:)`, `signIn(using:credentials:)`,
`signOut()`, `accessToken()`, `authorizedRequest(for:)`, `currentUser`,
`authState`, and `authStatePublisher`. Refresh tokens, Keychain access, and the
refresh scheduler are all internal and unreachable from app code.

## Providers

### Email / password (`AuthKitEmailPassword`)
REST-backed. Expects login/refresh endpoints returning
`{ access_token, refresh_token, expires_in, user }`.

### Phone OTP (`AuthKitPhoneOTP`)
Two steps: call `provider.requestCode(phoneNumber:)` to trigger the SMS, then
`signIn(using: .phoneOTP, credentials: PhoneOTPCredentials(phoneNumber:code:))`.

### Google (`AuthKitGoogle`) / Facebook (`AuthKitFacebook`)
Wrap the official SDKs. OAuth runs through `ASWebAuthenticationSession` for
system-level credential sharing (SSO), not an embedded web view. Sign in with
`NoCredentials()` — the SDK presents its own UI.

### Custom REST (`AuthKitRESTCustom`)
For any backend. You supply closures that build the login/refresh requests and
parse the response. Supports optional certificate pinning via `PinningConfig`
(opt-in here only, never forced on other providers).

## Adding a new sign-in method

Conform a type to `AuthProvider` (implement `authenticate`, `refresh`, and
optionally `signOut`) and pass it to `configure(providers:)`. Nothing else in
the package changes — that's the whole extension model.

## Examples

- **`Examples/ConsoleExample`** — a runnable, headless walkthrough of the full
  lifecycle (sign in → state publishing → automatic silent refresh → sign out)
  using an in-memory demo provider. Run it:

  ```
  swift run AuthKitConsoleExample
  ```

  You'll see the access token advance on its own (e.g. `#1` → `#3`) while the
  app just waits — that's the refresh scheduler working with no app involvement.

- **`Examples/SwiftUIDemo`** — reference SwiftUI integration (`@main` app,
  an `ObservableObject` bridge over the publisher, and a root view that swaps
  between signed-in and signed-out UI). Drop these files into an Xcode iOS app
  target and add the AuthKit dependency to run on a device/simulator.

## Testing

```
swift test
```

Core is covered by unit tests (`Tests/AuthKitCoreTests`) using a mock provider:
state transitions, sign-out, unregistered-provider handling, rejected
credentials, cached vs. expired token, and cold-launch session restore.

## Building the iOS-only providers

`AuthKitGoogle` and `AuthKitFacebook` depend on iOS-only SDKs, so `swift build`
on macOS can't compile them. Build them for an iOS destination:

```
xcodebuild build -scheme AuthKitGoogle   -destination "generic/platform=iOS Simulator"
xcodebuild build -scheme AuthKitFacebook -destination "generic/platform=iOS Simulator"
```
