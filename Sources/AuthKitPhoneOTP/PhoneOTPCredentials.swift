import AuthKitCore

/// Input for the second step of phone sign-in (verifying the code the user
/// received by SMS). The first step, sending that code, isn't part of
/// `AuthProvider.authenticate` because it doesn't produce an auth state —
/// call `PhoneOTPProvider.requestCode(phoneNumber:)` directly for that.
public struct PhoneOTPCredentials: AuthCredentials {
    public let phoneNumber: String
    public let code: String

    public init(phoneNumber: String, code: String) {
        self.phoneNumber = phoneNumber
        self.code = code
    }
}
