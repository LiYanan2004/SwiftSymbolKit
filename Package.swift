// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "CwlDemangle",
    products: [
        .library(name: "CwlDemangle", targets: ["CwlDemangle"]),
    ],
    targets: [
        .target(
            name: "CwlDemangle",
            path: "CwlDemangle",
            sources: ["CwlDemangle.swift"]
        ),
        .testTarget(
            name: "CwlDemangleTests",
            dependencies: ["CwlDemangle"],
            path: "CwlDemangleTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
