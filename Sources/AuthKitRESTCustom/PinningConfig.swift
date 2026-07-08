import Foundation

/// Opt-in certificate pinning for `CustomRESTProvider`. Left out of
/// AuthKitCore and every other provider entirely — Google/Facebook manage
/// their own transport security, and forcing pinning on every provider
/// would impose cert-rotation maintenance on apps that don't want it.
///
/// This pins the leaf certificate's SHA-256 hash (of the full DER
/// certificate), not just its public key — simpler and unambiguous, at the
/// cost of needing a config update whenever the server rotates its
/// certificate (even to a cert using the same key).
public struct PinningConfig: Sendable {
    public let pinnedCertificateHashes: Set<String>

    /// - Parameter pinnedCertificateHashes: base64-encoded SHA-256 hashes of
    ///   the DER-encoded server certificate(s) you trust.
    public init(pinnedCertificateHashes: Set<String>) {
        self.pinnedCertificateHashes = pinnedCertificateHashes
    }
}
