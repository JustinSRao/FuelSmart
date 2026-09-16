// swift-tools-version: 6.0
import PackageDescription

/// FuelSmartCore holds every domain model and every calculation.
///
/// It depends on Foundation and nothing else — no UI framework, no third-party
/// package, no network client. That keeps the financial model testable in
/// isolation and makes it impossible for a view to reach into the maths.
let package = Package(
    name: "FuelSmartCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "FuelSmartCore", targets: ["FuelSmartCore"]),
    ],
    targets: [
        .target(
            name: "FuelSmartCore",
            swiftSettings: [
                // ExistentialAny requires `any` on every existential, which the
                // sources already use.
                //
                // InternalImportsByDefault is deliberately NOT enabled: it makes
                // `import Foundation` internal, and this package's public API is
                // built from Foundation types (Date, UUID, Bundle, URL), so every
                // public signature would be rejected.
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "FuelSmartCoreTests",
            dependencies: ["FuelSmartCore"]
            // No `resources:` entry: the fixtures are Swift values in
            // Fixtures.swift, deliberately hand-written rather than loaded from
            // a bundled file, so no test can fail because a government dataset
            // was republished.
        ),
    ]
)
