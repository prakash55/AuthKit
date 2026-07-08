import Foundation
import AuthKitCore

/// REST-based email/password provider. Talks to two endpoints under
/// `baseURL`: a login endpoint and a refresh endpoint, both expected to
/// return `{ access_token, refresh_token, expires_in, user: {...} }`
/// (snake_case is decoded automatically).
///
/// Depends on nothing but Foundation + AuthKitCore, so it never pulls a
/// third-party SDK into an app that only needs email/password.
public final class EmailPasswordProvider: AuthProvider, Sendable {
    public let id: AuthProviderID = .emailPassword

    private let baseURL: URL
    private let loginPath: String
    private let refreshPath: String
    private let session: URLSession

    public init(
        baseURL: URL,
        loginPath: String = "auth/login",
        refreshPath: String = "auth/refresh",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.loginPath = loginPath
        self.refreshPath = refreshPath
        self.session = session
    }

    public func authenticate(with credentials: any AuthCredentials) async throws -> AuthTokenSet {
        guard let credentials = credentials as? EmailPasswordCredentials else {
            throw AuthError.invalidCredentials
        }
        let body = LoginRequest(email: credentials.email, password: credentials.password)
        return try await post(path: loginPath, body: body)
    }

    public func refresh(using refreshToken: String) async throws -> AuthTokenSet {
        let body = RefreshRequest(refreshToken: refreshToken)
        return try await post(path: refreshPath, body: body)
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> AuthTokenSet {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response): (Data, URLResponse)
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
                providerID: .emailPassword,
                displayName: payload.user.name,
                email: payload.user.email
            )
        )
    }
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let user: UserPayload
}

private struct UserPayload: Decodable {
    let id: String
    let email: String?
    let name: String?
}
