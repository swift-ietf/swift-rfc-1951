# swift-rfc-1951

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

DEFLATE compression and decompression as specified in RFC 1951.

## Standard Reference

- **RFC**: 1951
- **Title**: DEFLATE Compressed Data Format Specification

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/swift-ietf/swift-rfc-1951.git", from: "0.1.0")
]
```

Add the product to a target that needs it:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "RFC 1951", package: "swift-rfc-1951")
    ]
)
```

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
