import Foundation

/// Marker protocol for provider input. Each provider module defines its own
/// concrete credentials type conforming to this — AuthKitCore never needs to
/// know the shape of any specific provider's input, which is what lets new
/// auth types be added later without touching this package.
public protocol AuthCredentials: Sendable {}

/// Convenience credentials for providers that need no upfront input because
/// they drive their own UI (e.g. Google/Facebook present their own sign-in
/// sheet before AuthKit ever sees a token).
public struct NoCredentials: AuthCredentials {
    public init() {}
}
