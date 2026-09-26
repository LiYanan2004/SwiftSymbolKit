// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftSymbolKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwiftDemangle", targets: ["SwiftDemangle"]),
        .library(name: "SwiftSymbolIndex", targets: ["SwiftSymbolIndex"]),
        .executable(name: "swift-symbol", targets: ["SwiftSymbolCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftSymbolCLI",
            dependencies: [
                "SwiftSymbolIndex",
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
            name: "SwiftSymbolIndex",
            dependencies: ["SwiftDemangle"],
            path: "Sources/SwiftSymbolIndex"
        ),
        .testTarget(
            name: "SwiftSymbolIndexTests",
            dependencies: ["SwiftSymbolIndex", "SwiftDemangle"],
            path: "Tests/SwiftSymbolIndexTests",
            exclude: ["Fixtures"]
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
