// swift-tools-version:6.0

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
            path: "SwiftDemangle"
        ),
        .target(
            name: "SwiftSymbolIndex",
            dependencies: ["SwiftDemangle"],
            path: "SwiftSymbolIndex"
        ),
        .testTarget(
            name: "SwiftSymbolIndexTests",
            dependencies: ["SwiftSymbolIndex", "SwiftDemangle"],
            path: "SwiftSymbolIndexTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "SwiftDemangleTests",
            dependencies: ["SwiftDemangle"],
            path: "SwiftDemangleTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
