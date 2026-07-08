import AuthenticationServices

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared `ASWebAuthenticationSession` wrapper for any OAuth-style provider
/// (Google, Facebook, or a future one). Deliberately not exposed publicly —
/// providers use it internally so no provider module has to reimplement
/// presentation-context handling.
///
/// Using `ASWebAuthenticationSession` instead of an embedded `WKWebView` is
/// what gives us system-level credential sharing (SSO with the Safari/System
/// session) and avoids the phishing-UX problem of an app rendering its own
/// login chrome.
public final class WebAuthSession: NSObject, @unchecked Sendable {
    public struct Options {
        /// `false` (default) shares cookies with the system browser, enabling
        /// silent SSO for users already signed in elsewhere. Set `true` for
        /// a private, no-SSO session.
        public var prefersEphemeralSession: Bool

        public init(prefersEphemeralSession: Bool = false) {
            self.prefersEphemeralSession = prefersEphemeralSession
        }
    }

    public override init() {
        super.init()
    }

    @MainActor
    public func authenticate(url: URL, callbackURLScheme: String, options: Options = Options()) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.network(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = options.prefersEphemeralSession
            session.start()
        }
    }
}

extension WebAuthSession: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
