#if canImport(UIKit)
import UIKit

/// Shared by any provider that needs to present its own sign-in UI
/// (Google, Facebook, or a future SDK-backed provider) so the logic for
/// finding the right view controller to present from lives in one place.
public enum AuthPresentationContext {
    @MainActor
    public static func topMostViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        return resolve(root)
    }

    @MainActor
    private static func resolve(_ base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return resolve(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return resolve(tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return resolve(presented)
        }
        return base
    }
}
#endif
