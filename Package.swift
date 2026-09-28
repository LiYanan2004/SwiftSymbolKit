// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftSymbolKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftSymbolKit",
            targets: [
                "SwiftDemangle",
                "SwiftSymbolIndexStore",
                "SwiftIndexing"
            ]
        ),
        .executable(name: "swift-symbol", targets: ["SwiftSymbolCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/swift-precompiled/swift-syntax.git", from: "603.0.2"),
    ],
    targets: [
        .target(name: "SwiftIndexing", dependencies: ["SwiftDemangle"]),
        .executableTarget(
            name: "SwiftSymbolCLI",
            dependencies: [
                "SwiftIndexing",
                "SwiftSymbolIndexStore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(name: "SwiftSymbolCLITests", dependencies: ["SwiftSymbolCLI"]),
        .target(
            name: "SwiftDemangle",
            path: "Sources/SwiftDemangle"
        ),
        .target(
            name: "SwiftSymbolIndexStore",
            dependencies: [
                "SwiftIndexing",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftBasicFormat", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .testTarget(name: "SwiftIndexingTests", dependencies: ["SwiftIndexing"]),
        .testTarget(
            name: "SwiftSymbolIndexStoreTests",
            dependencies: [
                "SwiftSymbolIndexStore", "SwiftIndexing", "SwiftDemangle",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            path: "Tests/SwiftSymbolIndexStoreTests",
            exclude: ["Fixtures"],
            resources: [.copy("TestData")]
        ),
        .testTarget(
            name: "SwiftDemangleTests",
            dependencies: ["SwiftDemangle"],
            path: "Tests/SwiftDemangleTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
