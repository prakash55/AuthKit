import AuthKitCore

public struct EmailPasswordCredentials: AuthCredentials {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}
