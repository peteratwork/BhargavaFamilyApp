// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BhargavaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BhargavaCore", targets: ["BhargavaCore"])
    ],
    targets: [
        .target(name: "BhargavaCore"),
        .testTarget(name: "BhargavaCoreTests", dependencies: ["BhargavaCore"])
    ]
)
