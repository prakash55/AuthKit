import AuthKitCore

/// Arbitrary key/value input for a `CustomRESTProvider` — the provider
/// doesn't know your backend's field names, so it hands this straight to
/// your `authenticateRequest` closure to serialize however you need.
public struct CustomCredentials: AuthCredentials {
    public let fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }
}
