// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HealthCore", targets: ["HealthCore"])
    ],
    targets: [
        .target(name: "HealthCore"),
        .testTarget(name: "HealthCoreTests", dependencies: ["HealthCore"])
    ]
)
