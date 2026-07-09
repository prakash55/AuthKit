import AuthKitCore

/// Input for `AuthKitFirebase`, covering the sign-in methods Firebase Auth
/// supports through one provider. All associated values are strings, so the
/// type is trivially `Sendable`.
///
/// For OAuth methods (Google here, and Facebook/Apple if you add them) you
/// first obtain the provider's own tokens with its SDK, then hand them to
/// Firebase via these cases — Firebase exchanges them for its own session.
public enum FirebaseCredentials: AuthCredentials {
    /// Email + password. Use with `signIn` for existing accounts and `signUp`
    /// to create a new one.
    case emailPassword(email: String, password: String)

    /// Phone auth. `verificationID` comes from
    /// `FirebaseAuthProvider.verifyPhoneNumber(_:)`; `verificationCode` is the
    /// SMS code the user entered.
    case phone(verificationID: String, verificationCode: String)

    /// Google, bridged into Firebase. Obtain `idToken`/`accessToken` from the
    /// GoogleSignIn SDK (or AuthKitGoogle) first.
    case google(idToken: String, accessToken: String)
}
