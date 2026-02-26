// swift-tools-version: 6.2

import PackageDescription

// RFC 1951: DEFLATE Compressed Data Format Specification
let package = Package(
    name: "swift-rfc-1951",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "RFC 1951", targets: ["RFC 1951"])
    ],
    dependencies: [
        .package(path: "../../swift-primitives/swift-standard-library-extensions")
    ],
    targets: [
        .target(
            name: "RFC 1951",
            dependencies: [
                .product(name: "Standard Library Extensions", package: "swift-standard-library-extensions")
            ]
        ),
        .testTarget(
            name: "RFC 1951 Tests",
            dependencies: [
                "RFC 1951",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

extension String {
    var tests: Self { self + " Tests" }
}

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
