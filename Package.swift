// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftDemangle",
    products: [
        .library(name: "SwiftDemangle", targets: ["SwiftDemangle"]),
        .library(name: "SwiftSymbolIndex", targets: ["SwiftSymbolIndex"]),
    ],
    targets: [
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
            path: "Tests/SwiftDemangleTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
