// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UI16Controller",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "UI16Controller", targets: ["UI16Controller"])
    ],
    targets: [
        .target(name: "UI16Controller", path: "Sources/UI16Controller"),
        .testTarget(name: "UI16ProtocolTests", dependencies: ["UI16Controller"], path: "Tests")
    ]
)
