// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "tray_panel",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "tray-panel", targets: ["tray_panel"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "tray_panel",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/tray_panel"
        )
    ]
)
