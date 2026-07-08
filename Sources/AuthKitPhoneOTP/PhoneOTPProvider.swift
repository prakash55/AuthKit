import Foundation
import AuthKitCore

/// Phone number + SMS one-time-code provider. Sign-in is two steps:
/// 1. App calls `requestCode(phoneNumber:)` directly when the user submits
///    their number — this just triggers an SMS, it isn't routed through
///    `AuthManager` since it doesn't change auth state.
/// 2. When the user enters the code, the app calls
///    `AuthManager.shared.signIn(using: .phoneOTP, credentials: PhoneOTPCredentials(...))`,
///    which is what actually produces a session.
public final class PhoneOTPProvider: AuthProvider, Sendable {
    public let id: AuthProviderID = .phoneOTP

    private let baseURL: URL
    private let requestCodePath: String
    private let verifyPath: String
    private let refreshPath: String
    private let session: URLSession

    public init(
        baseURL: URL,
        requestCodePath: String = "auth/phone/request-code",
        verifyPath: String = "auth/phone/verify",
        refreshPath: String = "auth/refresh",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.requestCodePath = requestCodePath
        self.verifyPath = verifyPath
        self.refreshPath = refreshPath
        self.session = session
    }

    public func requestCode(phoneNumber: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(requestCodePath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["phone_number": phoneNumber])

        let (_, response) = try await performRequest(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AuthError.network("server returned status \(response.statusCode)")
        }
    }

    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let credentials = credentials as? PhoneOTPCredentials else {
            throw AuthError.invalidCredentials
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(verifyPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "phone_number": credentials.phoneNumber,
            "code": credentials.code
        ])
        return try await tokenSet(from: request)
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        var request = URLRequest(url: baseURL.appendingPathComponent(refreshPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        return try await tokenSet(from: request)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (data, http)
    }

    private func tokenSet(from request: URLRequest) async throws -> AuthTokenSet {
        let (data, http) = try await performRequest(request)
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            throw AuthError.network("server returned status \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(TokenResponse.self, from: data) else {
            throw AuthError.invalidServerResponse
        }

        return AuthTokenSet(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: Date().addingTimeInterval(payload.expiresIn),
            user: AuthUser(
                id: payload.user.id,
                providerID: .phoneOTP,
                displayName: payload.user.name,
                phoneNumber: payload.user.phoneNumber
            )
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let user: UserPayload
}

private struct UserPayload: Decodable {
    let id: String
    let phoneNumber: String?
    let name: String?
}
