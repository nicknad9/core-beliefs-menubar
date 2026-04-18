// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CorePrinciples",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "CorePrinciplesLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CorePrinciplesLib"
        ),
        .executableTarget(
            name: "CorePrinciples",
            dependencies: ["CorePrinciplesLib"],
            path: "Sources/CorePrinciples"
        ),
        .testTarget(
            name: "CorePrinciplesTests",
            dependencies: [
                "CorePrinciplesLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CorePrinciplesTests"
        ),
    ]
)
