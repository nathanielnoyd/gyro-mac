// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "gyro-mac",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GyroKit", targets: ["GyroKit"]),
        .executable(name: "gyro", targets: ["gyro"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "GyroKit"),
        .executableTarget(
            name: "gyro",
            dependencies: [
                "GyroKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "GyroKitTests",
            dependencies: ["GyroKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
