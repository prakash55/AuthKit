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

Every method follows the same two moves: register the provider in
`configure(providers:)`, then call `signIn(using:credentials:)`. Only the
credentials type differs. You can register several at once and let the user
pick — they all publish to the same `authStatePublisher`.

```swift
AuthManager.shared.configure(providers: [
    EmailPasswordProvider(baseURL: URL(string: "https://api.example.com")!),
    PhoneOTPProvider(baseURL: URL(string: "https://api.example.com")!),
    GoogleAuthProvider(clientID: "YOUR_GOOGLE_CLIENT_ID"),
    FacebookAuthProvider()
])
```

### Email / password (`AuthKitEmailPassword`)

REST-backed. Expects login/refresh endpoints returning
`{ access_token, refresh_token, expires_in, user }` (snake_case decoded
automatically).

```swift
import AuthKitEmailPassword

// Register (paths are customizable; defaults shown)
EmailPasswordProvider(
    baseURL: URL(string: "https://api.example.com")!,
    loginPath: "auth/login",
    refreshPath: "auth/refresh"
)

// Sign in
try await AuthManager.shared.signIn(
    using: .emailPassword,
    credentials: EmailPasswordCredentials(email: "user@example.com", password: "hunter2")
)
```

### Phone number + SMS OTP (`AuthKitPhoneOTP`)

Two steps. First trigger the SMS (this doesn't change auth state, so it's
called on the provider directly), then sign in with the code the user enters.

```swift
import AuthKitPhoneOTP

let phone = PhoneOTPProvider(baseURL: URL(string: "https://api.example.com")!)
AuthManager.shared.configure(providers: [phone])

// Step 1 — user submits their number
try await phone.requestCode(phoneNumber: "+15551234567")

// Step 2 — user enters the code they received
try await AuthManager.shared.signIn(
    using: .phoneOTP,
    credentials: PhoneOTPCredentials(phoneNumber: "+15551234567", code: "123456")
)
```

### Google (`AuthKitGoogle`)

Wraps the official GoogleSignIn SDK. OAuth runs through
`ASWebAuthenticationSession` for system-level credential sharing (SSO), not an
embedded web view. The SDK presents its own UI, so you sign in with
`NoCredentials()`.

```swift
import AuthKitGoogle

AuthManager.shared.configure(providers: [
    GoogleAuthProvider(clientID: "YOUR_GOOGLE_CLIENT_ID")
])

try await AuthManager.shared.signIn(using: .google, credentials: NoCredentials())
```

You still need the standard Google setup in your app: add your reversed client
ID as a URL scheme in `Info.plist` and forward the callback URL to
`GIDSignIn.sharedInstance.handle(_:)`.

### Facebook (`AuthKitFacebook`)

Wraps the official Facebook Login SDK. Also `NoCredentials()`; you can request
specific permissions at construction.

```swift
import AuthKitFacebook

AuthManager.shared.configure(providers: [
    FacebookAuthProvider(permissions: ["public_profile", "email"])
])

try await AuthManager.shared.signIn(using: .facebook, credentials: NoCredentials())
```

Complete the standard Facebook app setup (`FacebookAppID`, `CFBundleURLTypes`,
etc. in `Info.plist`) as the SDK requires.

### Custom REST (`AuthKitRESTCustom`)

For any backend that doesn't match the email/password shape. You supply
closures that build the login/refresh requests and parse the response, so
AuthKit never needs to know your field names.

```swift
import AuthKitRESTCustom

let acme = AuthProviderID(rawValue: "acme")

let provider = CustomRESTProvider(
    id: acme,
    // Opt-in certificate pinning — omit for standard ATS validation.
    pinning: PinningConfig(pinnedCertificateHashes: ["base64-sha256-of-der-cert"]),
    buildAuthenticateRequest: { credentials in
        guard let creds = credentials as? CustomCredentials else { throw AuthError.invalidCredentials }
        var request = URLRequest(url: URL(string: "https://acme.internal/token")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: creds.fields)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    },
    buildRefreshRequest: { refreshToken in
        var request = URLRequest(url: URL(string: "https://acme.internal/refresh")!)
        request.httpMethod = "POST"
        request.setValue(refreshToken, forHTTPHeaderField: "X-Refresh-Token")
        return request
    },
    parseResponse: { data, _ in
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return AuthTokenSet(
            accessToken: json["token"] as! String,
            refreshToken: json["refresh"] as? String,
            expiresAt: Date().addingTimeInterval(json["ttl"] as! TimeInterval),
            user: AuthUser(id: json["uid"] as! String, providerID: acme)
        )
    }
)

AuthManager.shared.configure(providers: [provider])

try await AuthManager.shared.signIn(
    using: acme,
    credentials: CustomCredentials(fields: ["username": "neo", "secret": "trinity"])
)
```

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
