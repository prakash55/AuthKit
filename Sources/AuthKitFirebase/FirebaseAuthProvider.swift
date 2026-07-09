import Foundation
import FirebaseAuth
import AuthKitCore

/// Firebase Authentication provider. One provider that handles several
/// sign-in methods (email/password, phone, Google) through `FirebaseCredentials`,
/// because Firebase itself is the backend for all of them.
///
/// Firebase manages its own token lifecycle and persists the session, so this
/// provider is a thin adapter: it converts Firebase's `User` into AuthKit's
/// `AuthTokenSet`, and `refresh` asks Firebase for a fresh ID token rather
/// than replaying a bare refresh-token string. AuthKit's own scheduler keeps
/// the ID token (which Firebase mints with a ~1h lifetime) fresh.
///
/// Requires the standard Firebase setup in your app: add `GoogleService-Info.plist`
/// and call `FirebaseApp.configure()` before any sign-in.
public final class FirebaseAuthProvider: AuthProvider, @unchecked Sendable {
    // Qualified because FirebaseAuth also exports a type named `AuthProviderID`.
    public let id: AuthKitCore.AuthProviderID = .firebase

    public init() {}

    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let credentials = credentials as? FirebaseCredentials else {
            throw AuthError.invalidCredentials
        }
        do {
            let result: AuthDataResult
            switch credentials {
            case .emailPassword(let email, let password):
                result = try await Auth.auth().signIn(withEmail: email, password: password)
            case .phone(let verificationID, let verificationCode):
                let credential = PhoneAuthProvider.provider().credential(
                    withVerificationID: verificationID,
                    verificationCode: verificationCode
                )
                result = try await Auth.auth().signIn(with: credential)
            case .google(let idToken, let accessToken):
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
                result = try await Auth.auth().signIn(with: credential)
            }
            return try await Self.tokenSet(from: result.user)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Only email/password supports a distinct sign-up (creating the account).
    /// Phone and Google create the account implicitly on first `signIn`, so
    /// `signUp` with those cases throws `AuthError.signUpNotSupported`.
    public func register(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let credentials = credentials as? FirebaseCredentials else {
            throw AuthError.invalidCredentials
        }
        guard case .emailPassword(let email, let password) = credentials else {
            throw AuthError.signUpNotSupported(id)
        }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            return try await Self.tokenSet(from: result.user)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        // Firebase holds the refresh token internally; force it to mint a new
        // ID token for the currently-signed-in user.
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: true)
            return try await Self.tokenSet(from: user)
        } catch {
            throw AuthError.refreshFailed(error.localizedDescription)
        }
    }

    public func signOut(userID: String) async {
        try? Auth.auth().signOut()
    }

    #if os(iOS)
    /// Step one of phone auth: triggers the SMS and returns a `verificationID`
    /// to pair with the code the user enters. Requires the standard Firebase
    /// phone-auth setup (APNs or reCAPTCHA fallback). iOS only.
    public func verifyPhoneNumber(_ phoneNumber: String) async throws -> String {
        do {
            return try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
        } catch {
            throw Self.mapped(error)
        }
    }
    #endif

    private static func tokenSet(from user: User) async throws -> AuthTokenSet {
        let tokenResult = try await user.getIDTokenResult(forcingRefresh: false)
        let authUser = AuthUser(
            id: user.uid,
            providerID: .firebase,
            displayName: user.displayName,
            email: user.email,
            phoneNumber: user.phoneNumber,
            photoURL: user.photoURL
        )
        return AuthTokenSet(
            accessToken: tokenResult.token,
            refreshToken: user.refreshToken,
            expiresAt: tokenResult.expirationDate,
            user: authUser
        )
    }

    /// Maps the common Firebase Auth error codes to AuthKit's errors. Uses the
    /// stable integer codes from `FIRAuthErrorDomain` so it doesn't depend on
    /// a particular Firebase SDK's Swift error-enum shape.
    private static func mapped(_ error: Error) -> AuthError {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            return .network(error.localizedDescription)
        }
        switch nsError.code {
        case 17004, // invalidCredential
             17007, // emailAlreadyInUse
             17008, // invalidEmail
             17009, // wrongPassword
             17011, // userNotFound
             17026: // weakPassword
            return .invalidCredentials
        case 17010: // tooManyRequests
            return .network("too many requests")
        case 17020: // networkError
            return .network(error.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }
}
