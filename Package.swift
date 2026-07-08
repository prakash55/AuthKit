// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuthKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "AuthKitCore", targets: ["AuthKitCore"]),
        .library(name: "AuthKitEmailPassword", targets: ["AuthKitEmailPassword"]),
        .library(name: "AuthKitGoogle", targets: ["AuthKitGoogle"]),
        .library(name: "AuthKitFacebook", targets: ["AuthKitFacebook"]),
        .library(name: "AuthKitPhoneOTP", targets: ["AuthKitPhoneOTP"]),
        .library(name: "AuthKitRESTCustom", targets: ["AuthKitRESTCustom"])
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.1.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", from: "17.0.0")
    ],
    targets: [
        // MARK: - Core (zero third-party dependencies)
        .target(
            name: "AuthKitCore",
            dependencies: []
        ),
        .testTarget(
            name: "AuthKitCoreTests",
            dependencies: ["AuthKitCore"]
        ),

        // MARK: - Providers (each depends only on Core + what it needs)
        .target(
            name: "AuthKitEmailPassword",
            dependencies: ["AuthKitCore"]
        ),
        .target(
            name: "AuthKitPhoneOTP",
            dependencies: ["AuthKitCore"]
        ),
        .target(
            name: "AuthKitRESTCustom",
            dependencies: ["AuthKitCore"]
        ),
        .target(
            name: "AuthKitGoogle",
            dependencies: [
                "AuthKitCore",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ]
        ),
        .target(
            name: "AuthKitFacebook",
            dependencies: [
                "AuthKitCore",
                .product(name: "FacebookLogin", package: "facebook-ios-sdk")
            ]
        ),

        // MARK: - Runnable example (swift run AuthKitConsoleExample)
        // Depends only on Core + EmailPassword, so it never pulls the
        // Google/Facebook SDKs and runs headless on macOS.
        .executableTarget(
            name: "AuthKitConsoleExample",
            dependencies: ["AuthKitCore", "AuthKitEmailPassword"],
            path: "Examples/ConsoleExample"
        )
    ]
)
