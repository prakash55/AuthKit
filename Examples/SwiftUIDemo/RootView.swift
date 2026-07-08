import SwiftUI
import AuthKitCore

/// Switches the whole app between signed-in and signed-out UI purely by
/// observing `AuthSession.state`. Because the state is published
/// continuously, this also updates automatically if a token refresh fails
/// (session ends) or a session is restored on launch — no extra wiring.
struct RootView: View {
    @StateObject private var session = AuthSession()

    var body: some View {
        switch session.state {
        case .authenticated(let user), .refreshing(let user):
            SignedInView(user: user)
                .environmentObject(session)
        case .authenticating:
            ProgressView("Signing in…")
        default:
            SignInView()
                .environmentObject(session)
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var session: AuthSession
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("AuthKit demo").font(.title.weight(.medium))

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button("Sign in with email") {
                Task { await session.signInWithEmail(email, password: password) }
            }
            .buttonStyle(.borderedProminent)

            // Button("Sign in with Google") {
            //     Task { await session.signInWithGoogle() }
            // }

            if case .error(let error) = session.state {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

struct SignedInView: View {
    @EnvironmentObject private var session: AuthSession
    let user: AuthUser

    var body: some View {
        VStack(spacing: 16) {
            Text("Signed in").font(.title.weight(.medium))
            Text(user.displayName ?? user.email ?? user.id)
            Text("via \(user.providerID.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Call my API (auto-attaches a fresh token)") {
                Task {
                    // AuthKit refreshes transparently if needed — the app
                    // never checks expiry itself.
                    let request = try? await AuthManager.shared.authorizedRequest(
                        for: URL(string: "https://api.example.com/me")!
                    )
                    print("Authorization header:", request?.value(forHTTPHeaderField: "Authorization") ?? "none")
                }
            }

            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
        }
        .padding()
    }
}
