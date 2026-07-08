import Foundation
import CryptoKit
import AuthKitCore

/// Generic REST provider for backends that don't match the shape
/// `AuthKitEmailPassword` assumes. You supply closures that build the
/// requests and parse the response; this type handles the network call,
/// error mapping, and (optionally) certificate pinning.
public final class CustomRESTProvider: NSObject, AuthProvider, URLSessionDelegate, @unchecked Sendable {
    public let id: AuthProviderID

    private let buildAuthenticateRequest: @Sendable (any AuthCredentials) throws -> URLRequest
    private let buildRefreshRequest: @Sendable (String) throws -> URLRequest
    private let parseResponse: @Sendable (Data, HTTPURLResponse) throws -> AuthTokenSet
    private let pinning: PinningConfig?
    private var session: URLSession = .shared

    /// - Parameters:
    ///   - id: a unique identifier for this backend, e.g. `AuthProviderID(rawValue: "acme-internal")`.
    ///   - pinning: optional certificate pinning; omit for standard ATS validation.
    ///   - buildAuthenticateRequest: given the credentials passed to `AuthManager.signIn`,
    ///     return the `URLRequest` to hit your login endpoint. Throw `AuthError.invalidCredentials`
    ///     if the concrete credentials type isn't what you expect.
    ///   - buildRefreshRequest: given a refresh token, return the `URLRequest` for your refresh endpoint.
    ///   - parseResponse: turn a successful HTTP response into an `AuthTokenSet`.
    public init(
        id: AuthProviderID,
        pinning: PinningConfig? = nil,
        buildAuthenticateRequest: @escaping @Sendable (any AuthCredentials) throws -> URLRequest,
        buildRefreshRequest: @escaping @Sendable (String) throws -> URLRequest,
        parseResponse: @escaping @Sendable (Data, HTTPURLResponse) throws -> AuthTokenSet
    ) {
        self.id = id
        self.pinning = pinning
        self.buildAuthenticateRequest = buildAuthenticateRequest
        self.buildRefreshRequest = buildRefreshRequest
        self.parseResponse = parseResponse
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        let request = try buildAuthenticateRequest(credentials)
        return try await run(request)
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        let request = try buildRefreshRequest(refreshToken)
        return try await run(request)
    }

    private func run(_ request: URLRequest) async throws -> AuthTokenSet {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            throw AuthError.network("server returned status \(http.statusCode)")
        }

        return try parseResponse(data, http)
    }

    // MARK: - Certificate pinning

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let pinning,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let matched = chain.contains { certificate in
            let certificateData = SecCertificateCopyData(certificate) as Data
            let hash = Data(SHA256.hash(data: certificateData)).base64EncodedString()
            return pinning.pinnedCertificateHashes.contains(hash)
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
