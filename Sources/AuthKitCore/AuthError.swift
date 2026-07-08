import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case providerNotRegistered(AuthProviderID)
    case invalidCredentials
    case cancelled
    case network(String)
    case invalidServerResponse
    case refreshFailed(String)
    case notAuthenticated
    case keychain(OSStatus)
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .providerNotRegistered(let id):
            return "No AuthProvider is registered for '\(id.rawValue)'. Pass it to AuthManager.configure(providers:)."
        case .invalidCredentials:
            return "The credentials passed don't match what this provider expects, or were rejected by the server."
        case .cancelled:
            return "The sign-in flow was cancelled."
        case .network(let message):
            return "Network error: \(message)"
        case .invalidServerResponse:
            return "The server returned a response AuthKit couldn't parse."
        case .refreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .notAuthenticated:
            return "No user is currently signed in."
        case .keychain(let status):
            return "Keychain error (OSStatus \(status))."
        }
    }
}
