// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MatrixNews",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "MatrixNewsCore",
            targets: ["MatrixNewsCore"]
        ),
        .executable(
            name: "matrix-news",
            targets: ["MatrixNewsApp"]
        ),
        .executable(
            name: "matrix-news-fetcher",
            targets: ["MatrixNewsFetcher"]
        )
    ],
    targets: [
        .target(
            name: "MatrixNewsCore"
        ),
        .executableTarget(
            name: "MatrixNewsApp",
            dependencies: ["MatrixNewsCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MatrixNewsFetcher",
            dependencies: ["MatrixNewsCore"]
        ),
        .testTarget(
            name: "MatrixNewsCoreTests",
            dependencies: ["MatrixNewsCore"]
        ),
        .testTarget(
            name: "MatrixNewsAppTests",
            dependencies: ["MatrixNewsApp", "MatrixNewsCore"]
        )
    ]
)
