// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmericanScaleKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AmericanScaleKit",
            targets: ["AmericanScaleKit"]
        )
    ],
    targets: [
        .target(
            name: "AmericanScaleKit"
        ),
        .testTarget(
            name: "AmericanScaleKitTests",
            dependencies: ["AmericanScaleKit"]
        )
    ]
)
