import AuthKitCore

public struct EmailPasswordCredentials: AuthCredentials {
    public let email: String
    public let password: String
    /// Optional profile name, sent only on `signUp`. Ignored on `signIn`.
    public let displayName: String?

    public init(email: String, password: String, displayName: String? = nil) {
        self.email = email
        self.password = password
        self.displayName = displayName
    }
}
