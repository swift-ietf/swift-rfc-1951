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
        .visionOS(.v26),
    ],
    products: [
        .library(name: "RFC 1951", targets: ["RFC 1951"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-standards/swift-standards", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "RFC 1951",
            dependencies: [
                .product(name: "Standards", package: "swift-standards"),
            ]
        ),
        .testTarget(
            name: "RFC 1951".tests,
            dependencies: ["RFC 1951"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

extension String {
    var tests: Self { self + " Tests" }
}

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
