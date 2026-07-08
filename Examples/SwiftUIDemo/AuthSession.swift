import Foundation
import Combine
import AuthKitCore
import AuthKitEmailPassword

/// Thin `ObservableObject` bridge so SwiftUI views can react to AuthKit's
/// Combine publisher with `@StateObject` / `@EnvironmentObject`. This is the
/// only glue an app writes — everything it exposes comes straight from
/// `AuthManager`.
@MainActor
final class AuthSession: ObservableObject {
    @Published private(set) var state: AuthState = .signedOut
    private var cancellable: AnyCancellable?

    init() {
        cancellable = AuthManager.shared.authStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.state = state
            }
    }

    var user: AuthUser? { state.user }

    func signInWithEmail(_ email: String, password: String) async {
        _ = try? await AuthManager.shared.signIn(
            using: .emailPassword,
            credentials: EmailPasswordCredentials(email: email, password: password)
        )
    }

    // func signInWithGoogle() async {
    //     _ = try? await AuthManager.shared.signIn(using: .google, credentials: NoCredentials())
    // }

    func signOut() async {
        await AuthManager.shared.signOut()
    }
}
