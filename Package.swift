// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "SwiftDemangle",
    products: [
        .library(name: "SwiftDemangle", targets: ["SwiftDemangle"]),
    ],
    targets: [
        .target(
            name: "SwiftDemangle",
            path: "SwiftDemangle"
        ),
        .testTarget(
            name: "SwiftDemangleTests",
            dependencies: ["SwiftDemangle"],
            path: "SwiftDemangleTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
