import SwiftUI
import AuthKitCore
import AuthKitEmailPassword
// import AuthKitGoogle    // add if you enable Google below
// import AuthKitFacebook  // add if you enable Facebook below

/// Entry point. The ONLY setup an app does is register its providers once.
/// After this, no screen in the app ever touches tokens or refresh logic —
/// they just observe `AuthSession`.
@main
struct AuthKitDemoApp: App {
    init() {
        AuthManager.shared.configure(providers: [
            EmailPasswordProvider(baseURL: URL(string: "https://api.example.com")!),
            // GoogleAuthProvider(clientID: "YOUR_GOOGLE_CLIENT_ID"),
            // FacebookAuthProvider()
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
