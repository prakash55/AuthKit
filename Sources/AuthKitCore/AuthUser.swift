import Foundation

/// A normalized identity, regardless of which `AuthProvider` produced it.
public struct AuthUser: Codable, Equatable, Sendable {
    public let id: String
    public let providerID: AuthProviderID
    public let displayName: String?
    public let email: String?
    public let phoneNumber: String?
    public let photoURL: URL?

    public init(
        id: String,
        providerID: AuthProviderID,
        displayName: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        photoURL: URL? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.photoURL = photoURL
    }
}

/// Identifies which `AuthProvider` a token set or credential belongs to.
/// A struct instead of an enum, so consumers can register custom providers
/// without ever needing to modify AuthKitCore.
public struct AuthProviderID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let emailPassword = AuthProviderID(rawValue: "emailPassword")
    public static let google = AuthProviderID(rawValue: "google")
    public static let facebook = AuthProviderID(rawValue: "facebook")
    public static let phoneOTP = AuthProviderID(rawValue: "phoneOTP")
    public static let firebase = AuthProviderID(rawValue: "firebase")
}

extension AuthProviderID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}
