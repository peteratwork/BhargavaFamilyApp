// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BhargavaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BhargavaCore", targets: ["BhargavaCore"]),
        .library(name: "BhargavaSupabase", targets: ["BhargavaSupabase"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            exact: "2.46.0"
        )
    ],
    targets: [
        .target(name: "BhargavaCore"),
        .target(
            name: "BhargavaSupabase",
            dependencies: [
                "BhargavaCore",
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(name: "BhargavaCoreTests", dependencies: ["BhargavaCore"]),
        .testTarget(
            name: "BhargavaSupabaseTests",
            dependencies: ["BhargavaCore", "BhargavaSupabase"]
        )
    ]
)
