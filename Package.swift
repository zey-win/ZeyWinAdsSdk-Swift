// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ZeyWinSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ZeyWinSDK",
            targets: ["ZeyWinSDK"]
        )
    ],
    targets: [
        .target(
            name: "ZeyWinSDK",
            dependencies: []
        ),
        .testTarget(
            name: "ZeyWinSDKTests",
            dependencies: ["ZeyWinSDK"]
        )
    ]
)
