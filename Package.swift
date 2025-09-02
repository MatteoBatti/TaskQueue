// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TaskQueue",
    platforms: [
        .macOS(.v10_15),
        .macCatalyst(.v13),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "TaskQueue",
            targets: ["TaskQueue"]),
    ],
    targets: [
        .target(
            name: "TaskQueue"),
        .testTarget(
            name: "TaskQueueTests",
            dependencies: ["TaskQueue"]
        ),
    ]
)
